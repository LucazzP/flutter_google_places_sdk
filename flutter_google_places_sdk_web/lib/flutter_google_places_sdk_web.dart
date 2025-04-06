@JS()
library places;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:js' as js;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_google_places_sdk_platform_interface/flutter_google_places_sdk_platform_interface.dart'
    as inter;
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:google_maps/google_maps.dart' as core;
import 'package:google_maps/google_maps_geocoding.dart' as geocoding;
import 'package:google_maps/google_maps_places.dart' as places;
import 'package:google_maps/google_maps_places.dart';
import 'package:web/web.dart' as web;

@JS('initMap')
external set _initMap(JSFunction f);

/// Web implementation plugin for flutter google places sdk
class FlutterGooglePlacesSdkWebPlugin extends inter.FlutterGooglePlacesSdkPlatform {
  /// Register the plugin with the web implementation.
  /// Called by ?? when ??
  static void registerWith(Registrar registrar) {
    inter.FlutterGooglePlacesSdkPlatform.instance = FlutterGooglePlacesSdkWebPlugin();
  }

  static const _SCRIPT_ID = 'flutter_google_places_sdk_web_script_id';

  Completer? _completer;

  AutocompleteService? _svcAutoComplete;
  PlacesService? _svcPlaces;
  AutocompleteSessionToken? _lastSessionToken;

  // Language
  String? _language;

  // Cache for photos
  final _photosCache = <String, PlacePhoto>{};
  var _runningUid = 1;

  @override
  Future<void> deinitialize() async {
    // Nothing to do; there is no de-initialize for web
  }

  @override
  Future<void> initialize(String apiKey, {Locale? locale, bool? useNewApi}) async {
    if (_svcAutoComplete != null) {
      return;
    }

    final completer = Completer();
    _completer = completer;

    _initMap = _doInit.toJS;

    web.Element? scriptExist = web.window.document.querySelector('#$_SCRIPT_ID');
    if (scriptExist != null) {
      bool googleMapsLoaded =
          js.context.hasProperty('google') && js.context['google'].hasProperty('maps');

      if (googleMapsLoaded) {
        _doInit();
      }
    } else {
      final body = web.window.document.querySelector('body')!;
      var src =
          'https://maps.googleapis.com/maps/api/js?key=${apiKey}&loading=async&libraries=places&callback=initMap';
      if (locale?.languageCode != null) {
        _language = locale?.languageCode;
      }
      body.append(web.HTMLScriptElement()
        ..id = _SCRIPT_ID
        ..src = src
        ..async = true
        ..type = 'application/javascript');
    }

    return completer.future.then((_) {});
  }

  @override
  Future<void> updateSettings(String apiKey, {Locale? locale, bool? useNewApi}) async {
    if (locale != null) {
      _language = locale.languageCode;
    }
  }

  void _doInit() {
    _svcAutoComplete = AutocompleteService();
    _svcPlaces = PlacesService(web.window.document.createElement('div') as web.HTMLElement);
    _completer!.complete();
  }

  @override
  Future<bool?> isInitialized() async {
    return _completer?.isCompleted == true;
  }

  AutocompleteSessionToken _getSessionToken({required bool force}) {
    final localToken = _lastSessionToken;
    if (force || localToken == null) {
      return AutocompleteSessionToken();
    }
    return localToken;
  }

  @override
  Future<inter.FindAutocompletePredictionsResponse> findAutocompletePredictions(
    String query, {
    List<String>? countries,
    List<String> placeTypesFilter = const [],
    bool? newSessionToken,
    inter.LatLng? origin,
    inter.LatLngBounds? locationBias,
    inter.LatLngBounds? locationRestriction,
  }) async {
    await _completer;
    final sessionToken = _getSessionToken(force: newSessionToken == true);
    _lastSessionToken = sessionToken;
    final prom = _svcAutoComplete!.getPlacePredictions(AutocompletionRequest(
      input: query,
      origin: origin == null ? null : core.LatLng(origin.lat, origin.lng),
      types: placeTypesFilter.isEmpty ? null : placeTypesFilter.map((e) => e.toJS).toList().toJS,
      componentRestrictions:
          ComponentRestrictions(country: countries?.map((e) => e.toJS).toList().toJS),
      locationBias: _boundsToWeb(locationBias),
      locationRestriction: _boundsToWeb(locationRestriction),
      language: _language,
      sessionToken: sessionToken,
    ));
    final resp = await prom;

    final predictions = resp.predictions.nonNulls.map(_translatePrediction).toList(growable: false);
    return inter.FindAutocompletePredictionsResponse(predictions);
  }

  inter.AutocompletePrediction _translatePrediction(places.AutocompletePrediction prediction) {
    var main_text = prediction.structuredFormatting.mainText;
    var secondary_text = prediction.structuredFormatting.secondaryText;
    return inter.AutocompletePrediction(
      distanceMeters: prediction.distanceMeters?.toInt() ?? 0,
      placeId: prediction.placeId,
      primaryText: main_text,
      secondaryText: secondary_text,
      fullText: '$main_text, $secondary_text',
    );
  }

  @override
  Future<inter.FetchPlaceResponse> fetchPlace(
    String placeId, {
    required List<inter.PlaceField> fields,
    bool? newSessionToken,
    String? regionCode,
  }) async {
    final sessionToken = _getSessionToken(force: newSessionToken == true);
    final prom = _getDetails(PlaceDetailsRequest()
      ..placeId = placeId
      ..fields = fields.map(this._mapField).toList(growable: false)
      ..sessionToken = sessionToken
      ..language = _language);

    final resp = await prom;
    return inter.FetchPlaceResponse(resp.place);
  }

  String _mapField(inter.PlaceField field) {
    switch (field) {
      case inter.PlaceField.Address:
        return 'formatted_address';
      case inter.PlaceField.AddressComponents:
        return 'address_components';
      case inter.PlaceField.BusinessStatus:
        return 'business_status';
      case inter.PlaceField.Id:
        return 'place_id';
      case inter.PlaceField.Location:
        return 'geometry.location';
      case inter.PlaceField.Name:
        return 'name';
      case inter.PlaceField.OpeningHours:
        return 'opening_hours';
      case inter.PlaceField.PhoneNumber:
        return 'international_phone_number';
      case inter.PlaceField.PhotoMetadatas:
        return 'photos';
      case inter.PlaceField.PlusCode:
        return 'plus_code';
      case inter.PlaceField.PriceLevel:
        return 'price_level';
      case inter.PlaceField.Rating:
        return 'rating'; // not done yet
      case inter.PlaceField.Types:
        return 'types';
      case inter.PlaceField.UserRatingsTotal:
        return 'user_ratings_total';
      case inter.PlaceField.UTCOffset:
        return 'utc_offset_minutes';
      case inter.PlaceField.Viewport:
        return 'geometry.viewport';
      case inter.PlaceField.WebsiteUri:
        return 'website';
      case inter.PlaceField.CurbsidePickup:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.CurrentOpeningHours:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.Delivery:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.DineIn:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.EditorialSummary:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.IconBackgroundColor:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.IconUrl:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.Reservable:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.Reviews:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.SecondaryOpeningHours:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.ServesBeer:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.ServesBreakfast:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.ServesBrunch:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.ServesDinner:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.ServesLunch:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.ServesVegetarianFood:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.ServesWine:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.Takeout:
        // TODO: Handle this case.
        throw UnimplementedError();
      case inter.PlaceField.WheelchairAccessibleEntrance:
        // TODO: Handle this case.
        throw UnimplementedError();
    }
  }

  Future<_GetDetailsResponse> _getDetails(PlaceDetailsRequest request) {
    final completer = Completer<_GetDetailsResponse>();

    final func = (PlaceResult? place, PlacesServiceStatus? status) {
      completer.complete(_GetDetailsResponse(_parsePlace(place), status));
    };

    _svcPlaces!.getDetails(request, func.toJS);

    return completer.future;
  }

  inter.Place? _parsePlace(PlaceResult? place) {
    if (place == null) {
      return null;
    }

    return inter.Place(
      id: place.placeId,
      address: place.formattedAddress,
      addressComponents: place.addressComponents
          ?.map(_parseAddressComponent)
          .cast<inter.AddressComponent>()
          .toList(growable: false),
      businessStatus: _parseBusinessStatus(place.getProperty('business_status'.toJS) as String?),
      attributions: place.htmlAttributions?.cast<String>(),
      latLng: _parseLatLang(place.geometry?.location),
      name: place.name,
      openingHours: _parseOpeningHours(place.openingHours),
      phoneNumber: place.internationalPhoneNumber,
      photoMetadatas: place.photos
          ?.map((photo) => _parsePhotoMetadata(photo))
          .cast<inter.PhotoMetadata>()
          .toList(growable: false),
      nameLanguageCode: null,
      plusCode: _parsePlusCode(place.plusCode),
      priceLevel: place.priceLevel?.toInt(),
      rating: place.rating?.toDouble(),
      types: place.types
          ?.map(_parsePlaceType)
          .where((item) => item != null)
          .cast<inter.PlaceType>()
          .toList(growable: false),
      userRatingsTotal: place.userRatingsTotal?.toInt(),
      utcOffsetMinutes: place.utcOffsetMinutes?.toInt(),
      viewport: _parseLatLngBounds(place.geometry?.viewport),
      websiteUri: place.website == null ? null : Uri.parse(place.website!),
      reviews: null,
    );
  }

  inter.PlaceType? _parsePlaceType(String? placeType) {
    if (placeType == null) {
      return null;
    }

    placeType = placeType.toUpperCase();
    return inter.PlaceType.values
        .cast<inter.PlaceType?>()
        .firstWhere((element) => element!.value == placeType, orElse: () => null);
  }

  inter.AddressComponent? _parseAddressComponent(
      geocoding.GeocoderAddressComponent? addressComponent) {
    if (addressComponent == null) {
      return null;
    }

    return inter.AddressComponent(
      name: addressComponent.longName,
      shortName: addressComponent.shortName,
      types: addressComponent.types.nonNulls
          .map((e) => e.toString())
          .cast<String>()
          .toList(growable: false),
    );
  }

  inter.LatLng? _parseLatLang(core.LatLng? location) {
    if (location == null) {
      return null;
    }

    return inter.LatLng(
      lat: location.lat.toDouble(),
      lng: location.lng.toDouble(),
    );
  }

  inter.PhotoMetadata? _parsePhotoMetadata(PlacePhoto? photo) {
    if (photo == null) {
      return null;
    }

    final htmlAttrs = photo.htmlAttributions.nonNulls.toList(growable: false);
    final photoMetadata = inter.PhotoMetadata(
        photoReference: _getPhotoMetadataReference(photo),
        width: photo.width.toInt(),
        height: photo.height.toInt(),
        attributions: htmlAttrs.length == 1 ? htmlAttrs[0] : '');

    _photosCache[photoMetadata.photoReference] = photo;

    return photoMetadata;
  }

  String _getPhotoMetadataReference(PlacePhoto photo) {
    final num = _runningUid++;
    return "id_${num.toString()}";
  }

  inter.LatLngBounds? _parseLatLngBounds(core.LatLngBounds? viewport) {
    if (viewport == null) {
      return null;
    }

    return inter.LatLngBounds(
        southwest: _parseLatLang(viewport.southWest)!,
        northeast: _parseLatLang(viewport.northEast)!);
  }

  inter.PlusCode? _parsePlusCode(PlacePlusCode? plusCode) {
    if (plusCode == null) {
      return null;
    }

    return inter.PlusCode(
      compoundCode: plusCode.compoundCode ?? '',
      globalCode: plusCode.globalCode,
    );
  }

  inter.BusinessStatus? _parseBusinessStatus(String? businessStatus) {
    if (businessStatus == null) {
      return null;
    }

    businessStatus = businessStatus.toUpperCase();
    return inter.BusinessStatus.values
        .firstWhereOrNull((element) => element.name.toUpperCase() == businessStatus);
  }

  inter.OpeningHours? _parseOpeningHours(PlaceOpeningHours? openingHours) {
    if (openingHours == null) {
      return null;
    }

    return inter.OpeningHours(
      periods:
          openingHours.periods?.nonNulls.map(_parsePeriod).cast<inter.Period>().toList(growable: false) ??
              [],
      weekdayText: openingHours.weekdayText?.nonNulls.cast<String>().toList(growable: false) ?? [],
    );
  }

  inter.Period _parsePeriod(PlaceOpeningHoursPeriod period) {
    return inter.Period(open: _parseTimeOfWeek(period.open)!, close: _parseTimeOfWeek(period.close));
  }

  inter.TimeOfWeek? _parseTimeOfWeek(PlaceOpeningHoursTime? timeOfWeek) {
    if (timeOfWeek == null) {
      return null;
    }

    final day = timeOfWeek.day.toInt();

    return inter.TimeOfWeek(
      day: _parseDayOfWeek(day),
      time: inter.PlaceLocalTime(
        hours: timeOfWeek.hours.toInt(),
        minutes: timeOfWeek.minutes.toInt(),
      ),
    );
  }

  inter.DayOfWeek _parseDayOfWeek(int day) {
    return inter.DayOfWeek.values[day];
  }

  core.LatLngBounds? _boundsToWeb(inter.LatLngBounds? bounds) {
    if (bounds == null) {
      return null;
    }
    return core.LatLngBounds(_latLngToWeb(bounds.southwest), _latLngToWeb(bounds.northeast));
  }

  core.LatLng _latLngToWeb(inter.LatLng latLng) {
    return core.LatLng(latLng.lat, latLng.lng);
  }

  @override
  Future<inter.FetchPlacePhotoResponse> fetchPlacePhoto(
    inter.PhotoMetadata photoMetadata, {
    int? maxWidth,
    int? maxHeight,
  }) async {
    PlacePhoto? value = _photosCache[photoMetadata.photoReference];
    if (value == null) {
      throw PlatformException(
        code: 'API_ERROR_PHOTO',
        message: 'PhotoMetadata must be initially fetched with fetchPlace',
        details: '',
      );
    }

    final url = value.url;

    return inter.FetchPlacePhotoResponse.imageUrl(url);
  }
}

/// A Place details response returned from PlacesService
class _GetDetailsResponse {
  /// Construct a new response
  const _GetDetailsResponse(this.place, this.status);

  /// The place of the response.
  final inter.Place? place;

  /// The status of the response.
  final PlacesServiceStatus? status;
}
