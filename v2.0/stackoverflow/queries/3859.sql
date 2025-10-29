WITH
UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostDate,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
),
PostAgg AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScoreSum,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScoreSum,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN p.Tags IS NOT NULL THEN 1 ELSE 0 END) AS TaggedPostCount,
        -- emulate ARRAY_AGG(DISTINCT t) in dialects without FILTER/ARRAY types by aggregating distinct tags as a comma list
        -- then later split if needed; here keep as a comma-separated string
        STRING_AGG(DISTINCT t, ',') AS AllTags
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t
    ) tags ON TRUE
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS PostsWithTag,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LatestPostDate
    FROM Tags t
    JOIN Posts p
      ON p.Tags LIKE ('%' || '<' || t.TagName || '>' || '%')
    GROUP BY t.TagName
),
UserTagRank AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.NetVotes,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        COALESCE(pa.QuestionScoreSum, 0) AS QuestionScoreSum,
        COALESCE(pa.AnswerScoreSum, 0) AS AnswerScoreSum,
        COALESCE(pa.QuestionCount, 0) AS QuestionCount,
        COALESCE(pa.AnswerCount, 0) AS AnswerCount,
        COALESCE(pa.TaggedPostCount, 0) AS TaggedPostCount,
        -- convert comma list to array-like string; keep as AllTagsStr for portability
        COALESCE(pa.AllTags, '') AS AllTagsStr,
        ROW_NUMBER() OVER (ORDER BY (us.Reputation + us.NetVotes) DESC) AS RankByRepNet,
        ROW_NUMBER() OVER (PARTITION BY CASE WHEN us.GoldBadges > 0 THEN 1 ELSE 0 END ORDER BY us.Reputation DESC) AS RankGoldGroup,
        us.LastPostDate
    FROM UserStats us
    LEFT JOIN PostAgg pa ON pa.UserId = us.Id
)

SELECT
    utr.Id,
    utr.DisplayName,
    utr.Reputation,
    utr.NetVotes,
    utr.GoldBadges,
    utr.SilverBadges,
    utr.BronzeBadges,
    utr.QuestionScoreSum,
    utr.AnswerScoreSum,
    utr.QuestionCount,
    utr.AnswerCount,
    utr.TaggedPostCount,
    -- extract first tag from comma-separated AllTagsStr; dialects vary, use CASE with POSITION/SUBSTR
    CASE
      WHEN utr.AllTagsStr = '' THEN 'NoTag'
      WHEN POSITION(',' IN utr.AllTagsStr) = 0 THEN utr.AllTagsStr
      ELSE SUBSTR(utr.AllTagsStr, 1, POSITION(',' IN utr.AllTagsStr) - 1)
    END AS FirstTag,
    utr.RankByRepNet,
    utr.RankGoldGroup,
    CASE
        WHEN utr.LastPostDate IS NULL THEN 'Never posted'
        WHEN utr.LastPostDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY) THEN 'Active'
        ELSE 'Dormant'
    END AS ActivityStatus,
    COALESCE((
        -- join needs to split AllTagsStr; use a derived table to split comma list using string functions
        SELECT STRING_AGG(DISTINCT ts.TagName, ',')
        FROM (
          -- split utr.AllTagsStr into rows: many dialects lack a standard split; attempt generic approach using recursive CTE
          WITH RECURSIVE parts(str, rest) AS (
            SELECT
              CASE WHEN utr.AllTagsStr = '' THEN NULL ELSE
                CASE WHEN POSITION(',' IN utr.AllTagsStr) = 0 THEN utr.AllTagsStr ELSE SUBSTR(utr.AllTagsStr, 1, POSITION(',' IN utr.AllTagsStr) - 1) END
              END,
              CASE WHEN utr.AllTagsStr = '' THEN '' ELSE
                CASE WHEN POSITION(',' IN utr.AllTagsStr) = 0 THEN '' ELSE SUBSTR(utr.AllTagsStr, POSITION(',' IN utr.AllTagsStr) + 1) END
              END
            UNION ALL
            SELECT
              CASE WHEN POSITION(',' IN rest) = 0 THEN rest ELSE SUBSTR(rest, 1, POSITION(',' IN rest) - 1) END,
              CASE WHEN POSITION(',' IN rest) = 0 THEN '' ELSE SUBSTR(rest, POSITION(',' IN rest) + 1) END
            FROM parts
            WHERE rest <> ''
          )
          SELECT str AS tag FROM parts WHERE str IS NOT NULL AND str <> ''
        ) AS t(tag)
        JOIN TagStats ts ON ts.TagName = t.tag
        WHERE ts.PostsWithTag > 100
    ), 'None') AS PopularTagList
FROM UserTagRank utr
WHERE utr.RankByRepNet <= 100
   OR (utr.GoldBadges > 0 AND utr.AnswerCount > 0)

UNION ALL

SELECT
    NULL                     AS Id,
    '--- Summary ---'        AS DisplayName,
    NULL                     AS Reputation,
    NULL                     AS NetVotes,
    NULL                     AS GoldBadges,
    NULL                     AS SilverBadges,
    NULL                     AS BronzeBadges,
    SUM(QuestionScoreSum)    AS QuestionScoreSum,
    SUM(AnswerScoreSum)      AS AnswerScoreSum,
    SUM(QuestionCount)       AS QuestionCount,
    SUM(AnswerCount)         AS AnswerCount,
    SUM(TaggedPostCount)     AS TaggedPostCount,
    NULL                     AS FirstTag,
    NULL                     AS RankByRepNet,
    NULL                     AS RankGoldGroup,
    NULL                     AS ActivityStatus,
    NULL                     AS PopularTagList
FROM UserTagRank
WHERE RankByRepNet <= 100

ORDER BY RankByRepNet;