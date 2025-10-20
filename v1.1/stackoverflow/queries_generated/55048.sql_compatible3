WITH 
RecentQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= DATE '2022-01-01'
),
LatestEdits AS (
    SELECT 
        ph.PostId,
        MAX(ph.CreationDate) AS LastEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS HasEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY ph.PostId
),
VoteScores AS (
    SELECT 
        v.PostId,
        SUM(CASE 
                WHEN v.VoteTypeId = 2 THEN 1
                WHEN v.VoteTypeId = 3 THEN -1
                ELSE 0
            END) AS NetVoteScore
    FROM Votes v
    WHERE v.CreationDate >= DATE '2022-01-01'
    GROUP BY v.PostId
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
Numbers AS (
    SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
    UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
    UNION ALL SELECT 11 UNION ALL SELECT 12 UNION ALL SELECT 13 UNION ALL SELECT 14 UNION ALL SELECT 15
    UNION ALL SELECT 16 UNION ALL SELECT 17 UNION ALL SELECT 18 UNION ALL SELECT 19 UNION ALL SELECT 20
),
TagFrequencies AS (
    SELECT 
        TRIM(t.tag) AS Tag,
        COUNT(*) AS TagUseCount
    FROM (
        SELECT
            q.Id,
            CASE 
                WHEN q.Tags IS NULL THEN NULL
                ELSE
                    REPLACE(
                        REPLACE(
                            SUBSTRING(q.Tags FROM 2 FOR (CASE WHEN LENGTH(q.Tags) >= 2 THEN LENGTH(q.Tags) - 2 ELSE 0 END)),
                        '><', '|'),
                    '>', '')
            END AS TagsInner
        FROM RecentQuestions q
    ) qi
    JOIN Numbers num ON 1=1
    JOIN (
        SELECT NULL::text AS tag -- placeholder to be replaced per row via lateral-like logic
    ) dummy ON 1=1
    -- Since standard SQL doesn't have easy string-split with position loop, approximate by splitting first element and any single-part tags.
    -- Extract only single-tag or first tag occurrences to avoid complex iterative parsing in portable SQL.
    CROSS JOIN LATERAL (
        SELECT
            CASE
                WHEN qi.TagsInner IS NULL OR qi.TagsInner = '' THEN NULL
                WHEN POSITION('|' IN qi.TagsInner) = 0 THEN qi.TagsInner
                ELSE SUBSTRING(qi.TagsInner FROM 1 FOR POSITION('|' IN qi.TagsInner)-1)
            END AS tag
    ) t
    WHERE t.tag IS NOT NULL
      AND t.tag <> ''
    GROUP BY TRIM(t.tag)
),
TopTags AS (
    SELECT 
        Tag,
        TagUseCount,
        RANK() OVER (ORDER BY TagUseCount DESC) AS TagRank
    FROM TagFrequencies
    WHERE TagUseCount > 1000
),
QuestionMetrics AS (
    SELECT 
        q.Id,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.Tags,
        COALESCE(e.LastEditDate, q.CreationDate) AS LastActivityDate,
        COALESCE(v.NetVoteScore, 0) AS NetVoteScore,
        u.Reputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate DESC) AS UserQuestionRank,
        q.OwnerUserId
    FROM RecentQuestions q
    LEFT JOIN LatestEdits e      ON e.PostId = q.Id
    LEFT JOIN VoteScores v       ON v.PostId = q.Id
    LEFT JOIN Users u            ON u.Id = q.OwnerUserId
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = q.OwnerUserId
)
SELECT 
    qm.Id,
    qm.Title,
    qm.CreationDate,
    qm.Score,
    qm.ViewCount,
    qm.AnswerCount,
    qm.FavoriteCount,
    qm.NetVoteScore,
    qm.Reputation,
    qm.GoldBadges,
    qm.SilverBadges,
    qm.BronzeBadges,
    qm.UserQuestionRank,
    tt.Tag,
    tt.TagUseCount,
    tt.TagRank
FROM QuestionMetrics qm
LEFT JOIN (
    SELECT t.Tag, t.TagUseCount, t.TagRank, ROW_NUMBER() OVER (PARTITION BY t.Tag ORDER BY t.TagRank) as rn
    FROM TopTags t
) tt ON tt.Tag IN (
    -- derive tags from qm.Tags similarly to TagFrequencies simplified logic: take full tag string if single, else first tag
    SELECT CASE
             WHEN qm.Tags IS NULL THEN NULL
             ELSE
               REPLACE(
                 REPLACE(
                   SUBSTRING(qm.Tags FROM 2 FOR (CASE WHEN LENGTH(qm.Tags) >= 2 THEN LENGTH(qm.Tags) - 2 ELSE 0 END)),
                 '><', '|'),
               '>', '')
           END
) AND tt.rn <= 3
ORDER BY qm.NetVoteScore DESC, qm.ViewCount DESC
LIMIT 500;