WITH RecursiveTopKommentors AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(c.Id) FILTER (WHERE EXTRACT(YEAR FROM c.CreationDate) >= date_part('year', cast('2024-10-01' as date))) AS CommentCount
    FROM Users u
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
)
SELECT *
FROM RecursiveTopKommentors;