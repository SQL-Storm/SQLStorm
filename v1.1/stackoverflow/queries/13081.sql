WITH UserActivity AS (
    SELECT 
        OwnerUserId AS UserId, 
        COUNT(DISTINCT Id) AS PostsCreated,
        SUM(Score) AS TotalScore,
        MAX(CreationDate) AS LastPostCreationDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
TopTags AS (
    SELECT 
        TRIM(tag) AS Tag,
        COUNT(*) AS TagFrequency
    FROM Posts
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(Tags FROM 2 FOR LENGTH(Tags)-2), '><')) AS tag
    ) s
    WHERE PostTypeId = 1 AND Tags IS NOT NULL
    GROUP BY TRIM(tag)
),
UserTopTags AS (
    SELECT
        tmp.OwnerUserId AS UserId,
        STRING_AGG(tmp.Tag, ',' ORDER BY tmp.TagCount DESC) AS TopFiveTags
    FROM (
        SELECT
            p.OwnerUserId,
            TRIM(t.tag) AS Tag,
            COUNT(*) AS TagCount,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS rnk
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS tag
        ) t
        WHERE p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, TRIM(t.tag)
    ) tmp
    WHERE tmp.rnk <= 5
    GROUP BY tmp.OwnerUserId
),
PostEdits AS (
    SELECT
        ph.PostId,
        COUNT(*) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY ph.PostId
),
UserPerformance AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ua.PostsCreated,
        COALESCE(ua.TotalScore, 0) AS TotalScore,
        ROW_NUMBER() OVER (ORDER BY COALESCE(ua.TotalScore, 0) DESC) AS ScoreRank,
        utt.TopFiveTags,
        COALESCE(pe.EditCount, 0) AS EditCount,
        pe.LastEditDate
    FROM Users u
    LEFT JOIN UserActivity ua ON u.Id = ua.UserId
    LEFT JOIN UserTopTags utt ON u.Id = utt.UserId
    LEFT JOIN PostEdits pe ON pe.PostId = u.Id
    WHERE u.Reputation > 1000
)
SELECT
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.PostsCreated,
    up.TotalScore,
    up.ScoreRank,
    up.TopFiveTags,
    up.EditCount,
    up.LastEditDate,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = up.UserId AND b.Class = 1) AS GoldBadges,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = up.UserId AND p.PostTypeId = 2) AS AvgAnswerScore
FROM UserPerformance up
WHERE up.ScoreRank <= 100
ORDER BY up.ScoreRank;