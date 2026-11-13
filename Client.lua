local _, A = ...
-- Forever has its own talent trees; every reader of A.catalogs then follows the running client.
if A.forever and type(A.foreverCatalogs) == "table" then
    A.catalogs, A.catalogVersion = A.foreverCatalogs, A.foreverCatalogVersion
end
