WITH RecursiveTagsCTE AS (
    SELECT 
        P.Id AS PostId,
        TRIM(BOTH '<>' FROM X.Tag) AS Tag,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.OwnerUserId
    FROM Posts P,
    LATERAL (
        SELECT value AS Tag
        FROM UNNEST(
            CASE
                WHEN COALESCE(P.Tags, '') = '' THEN ARRAY[]::text[]
                ELSE regexp_split_to_array(TRIM(BOTH '<>' FROM COALESCE(P.Tags, '')), '><')
            END
        ) AS t(value)
    ) AS X
)
SELECT
    PostId,
    Tag,
    CreationDate,
    Score,
    ViewCount,
    AnswerCount,
    OwnerUserId
FROM RecursiveTagsCTE
GROUP BY
    PostId,
    Tag,
    CreationDate,
    Score,
    ViewCount,
    AnswerCount,
    OwnerUserId;