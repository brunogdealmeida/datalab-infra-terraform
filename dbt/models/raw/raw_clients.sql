select *
from {{ source('clients_source', 'clients') }}
