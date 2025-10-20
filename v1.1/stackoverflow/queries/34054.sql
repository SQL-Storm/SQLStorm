WITH RankedAnswers AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.CreationDate,
        a.Score,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
TopAnswers AS (
    SELECT *
    FROM RankedAnswers
    WHERE AnswerRank <= 3
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(COALESCE(p.Score,0)) AS TotalPostScore,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionTagStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        CASE
          WHEN q.Tags IS NULL OR q.Tags = '' THEN NULL
          ELSE (
            -- transform tags like '<tag1><tag2>' into an array by removing leading/trailing '<' and '>' and splitting on '><'
            -- Use standard SQL string functions where supported; for portability produce a delimited string here and split later where UNNEST is used.
            -- Remove leading '<' and trailing '>'
            REPLACE(
              TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM q.Tags)),
              '><',
              ','
            )
          )
        END AS TagListDelimited
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags
),
TagExplode AS (
    -- Turn the delimited tag string into rows (portable approach using a simple string-split function; many DBs provide SPLIT or STRING_TO_ARRAY; here use a generic approach with recursive CTE)
    SELECT
        QuestionId,
        CASE WHEN Tag = '' THEN NULL ELSE Tag END AS Tag,
        Score,
        ViewCount,
        AnswerCount
    FROM (
        SELECT
            QuestionId,
            Score,
            ViewCount,
            AnswerCount,
            -- recursive splitter will produce one row per tag
            regexp_split AS Tag
        FROM (
            SELECT
                QuestionId,
                Score,
                ViewCount,
                AnswerCount,
                -- fallback: if TagListDelimited is NULL then produce NULL tag; else use a simple split by ',' via regexp_split_to_table when available
                CASE
                  WHEN TagListDelimited IS NULL THEN NULL
                  ELSE TagListDelimited
                END AS TagListDelimited
            FROM QuestionTagStats
        ) t1,
        LATERAL (
          -- If the engine supports regexp_split_to_table or string_split, replace this LATERAL with that. For portability attempt regexp_split_to_table; if not available, engines will need adaptation.
          SELECT value AS regexp_split
          FROM (
            SELECT regexp_split_to_table(t1.TagListDelimited, ',') AS value
          ) s
        ) s2
    ) x
),
TagAggregate AS (
    SELECT 
        Tag,
        COUNT(DISTINCT QuestionId) AS QuestionCount,
        AVG(Score) AS AvgQuestionScore,
        AVG(ViewCount) AS AvgQuestionViews,
        AVG(AnswerCount) AS AvgAnswerCount
    FROM TagExplode
    WHERE Tag IS NOT NULL
    GROUP BY Tag
),
CloseReasonCounts AS (
    SELECT 
        cht.Name AS CloseReason,
        COUNT(ph.Id) AS CloseCount
    FROM PostHistory ph
    JOIN CloseReasonTypes cht ON CAST(ph.Comment AS INTEGER) = cht.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY cht.Name
),
QuestionTagsOrdered AS (
    SELECT
        qts.QuestionId,
        t.Tag,
        t.QuestionCount,
        ROW_NUMBER() OVER (PARTITION BY qts.QuestionId ORDER BY t.QuestionCount DESC, t.Tag) AS rn
    FROM QuestionTagStats qts
    LEFT JOIN TagAggregate t ON t.Tag IN (
        -- expand the delimited tag list into a set for join; using LIKE as portable fallback
        -- This is less efficient but avoids non-inner join on subquery issues in some engines
        SELECT split_tag FROM (
          SELECT regexp_split_to_table(qts.TagListDelimited, ',') AS split_tag
        ) st
    )
)
SELECT 
    qts.QuestionId,
    qts.Title,
    qts.CreationDate,
    qts.Score AS QuestionScore,
    qts.ViewCount,
    qts.AnswerCount,
    ta.AnswerId,
    ta.Score AS AnswerScore,
    u.DisplayName AS Answerer,
    u.Reputation AS AnswererReputation,
    us.TotalPosts AS AnswererTotalPosts,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    ta.CreationDate AS AnswerCreationDate,
    (
      SELECT ARRAY_AGG(qto.Tag ORDER BY qto.QuestionCount DESC, qto.Tag)
      FROM QuestionTagsOrdered qto
      WHERE qto.QuestionId = qts.QuestionId
    ) AS TopTags,
    crc.CloseReason,
    crc.CloseCount
FROM QuestionTagStats qts
LEFT JOIN TopAnswers ta ON ta.QuestionId = qts.QuestionId
LEFT JOIN Users u ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = ta.AnswerId)
LEFT JOIN UserStats us ON us.UserId = u.Id
LEFT JOIN CloseReasonCounts crc ON 1=1
WHERE qts.Score >= 5
GROUP BY 
    qts.QuestionId, qts.Title, qts.CreationDate, qts.Score, qts.ViewCount, qts.AnswerCount,
    ta.AnswerId, ta.Score, u.DisplayName, u.Reputation, us.TotalPosts, us.GoldBadges, us.SilverBadges, us.BronzeBadges, ta.CreationDate,
    crc.CloseReason, crc.CloseCount
ORDER BY qts.Score DESC, ta.Score DESC, qts.ViewCount DESC
LIMIT 100;