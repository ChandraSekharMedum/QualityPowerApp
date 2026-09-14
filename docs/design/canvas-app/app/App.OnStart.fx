// ============================================================================
// App.OnStart — runs once when the app launches.
// Order: 1) theme  2) company/context  3) warm lookup caches  4) route to Home.
//
// Keep OnStart lean: only cache the SMALL, always-needed lookups here. Large or
// query-as-you-type lists (sales orders, batches) are pulled on demand by the
// screen that needs them, not up front.
// ============================================================================

// 1) Theme + home tiles — paste the contents of theme.fx here first, OR call a
//    theme component. (This file assumes theme.fx has already run.)

// 2) Company / user context ---------------------------------------------------
// Legal entities the user can work in. Replace with your dataAreaId codes, or
// load from a lookup flow if it varies per user.
ClearCollect(colCompanies,
    { code: "usmf", name: "USMF — Contoso Retail" },
    { code: "usrt", name: "USRT — Contoso Entertainment" }
);
Set(gCompany, First(colCompanies));          // active legal entity; changeable in Settings
Set(gUser, { name: User().FullName, email: User().Email });

// 3) Warm small lookup caches via read flows ---------------------------------
// Each returns a JSON string; we parse to a typed table. Guarded so a slow
// network doesn't block launch — screens re-pull on Refresh if empty.
Set(gLoadErr, "");
IfError(
    ClearCollect(colTestGroups,
        ForAll(Table(ParseJSON(Lookup_TestGroups.Run(gCompany.code).items)) As r,
            { id: Text(r.Value.QualityTestGroupId), name: Text(r.Value.Description) }
        )
    ),
    Set(gLoadErr, "Test groups: " & FirstError.Message)
);
IfError(
    ClearCollect(colProblemTypes,
        ForAll(Table(ParseJSON(Lookup_ProblemTypes.Run(gCompany.code).items)) As r,
            { id: Text(r.Value.ProblemTypeId), name: Text(r.Value.Description) }
        )
    ),
    Set(gLoadErr, gLoadErr & "  Problem types: " & FirstError.Message)
);
IfError(
    ClearCollect(colDispositionCodes,
        ForAll(Table(ParseJSON(Lookup_DispositionCodes.Run(gCompany.code).items)) As r,
            { code: Text(r.Value.DispositionCode), name: Text(r.Value.Description) }
        )
    ),
    Set(gLoadErr, gLoadErr & "  Disposition codes: " & FirstError.Message)
);

// Source pickers (static — drive the QO/NC/TR menus as data) ------------------
ClearCollect(colQOSources,
    { key: "Sales", label: "Sales", icon: Icon.Cart },
    { key: "Purchase", label: "Purchase", icon: Icon.Trolley },
    { key: "Inventory", label: "Inventory", icon: Icon.Shop },
    { key: "Production", label: "Production", icon: Icon.Settings },
    { key: "RouteOperation", label: "Route Operation", icon: Icon.Sort },
    { key: "CoProduct", label: "Co-Product Production", icon: Icon.Diamond },
    { key: "Quarantine", label: "Quarantine", icon: Icon.Lock }
);
ClearCollect(colNCSources,
    { key: "Internal", label: "Internal", icon: Icon.Home },
    { key: "Customer", label: "Customer", icon: Icon.Person },
    { key: "Vendor", label: "Vendor", icon: Icon.Trolley },
    { key: "Service", label: "Service Request", icon: Icon.Support },
    { key: "Production", label: "Production", icon: Icon.Settings },
    { key: "CoProduct", label: "Co-product Production", icon: Icon.Diamond }
);
// Test Results reuses the same 7 sources as Quality Order.

// 4) Route --------------------------------------------------------------------
Set(gBusy, false);
Set(gRes, Blank());
Navigate(scrHome, ScreenTransition.None);
