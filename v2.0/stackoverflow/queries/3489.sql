-- {"query": "3489.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1964}
WITH
BadgeCounts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCnt,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCnt,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCnt,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostAgg AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS ACount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS QScoreSum,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS AScoreSum,
        COALESCE(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END), 0) AS AvgAnswerScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
LatestComment AS (
    SELECT
        c.UserId,
        c.Text AS CommentText,
        c.CreationDate AS CommentDate,
        ROW_NUMBER() OVER (PARTITION BY c.UserId ORDER BY c.CreationDate DESC) AS rn
    FROM Comments c
    WHERE c.UserId IS NOT NULL
),
UserTagRanks AS (
    SELECT
        p.OwnerUserId AS UserId,
        t.tag AS Tag,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS TagRank,
        COUNT(*) AS TagUseCnt
    FROM Posts p
    JOIN LATERAL (
        SELECT TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags)) AS trimmed_tags
    ) _tt ON TRUE
    JOIN LATERAL (
        SELECT unnest(string_to_array(_tt.trimmed_tags, '><')) AS tag
    ) t ON TRUE
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, t.tag
    HAVING COUNT(*) > 0
),
TopTags AS (
    SELECT
        utr.UserId,
        STRING_AGG(utr.Tag, ', ') FILTER (WHERE utr.TagRank <= 3) AS Top3Tags
    FROM UserTagRanks utr
    GROUP BY utr.UserId
),
GoldAndDupClose AS (
    SELECT DISTINCT
        u.Id
    FROM Users u
    JOIN BadgeCounts bc ON bc.UserId = u.Id AND bc.GoldCnt > 0
    JOIN Posts q ON q.OwnerUserId = u.Id AND q.PostTypeId = 1
    JOIN PostHistory ph ON ph.PostId = q.Id
                       AND ph.PostHistoryTypeId = 10
    WHERE ph.Comment = '101'
),
UserCombined AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(bc.GoldCnt, 0) AS GoldBadges,
        COALESCE(bc.SilverCnt, 0) AS SilverBadges,
        COALESCE(bc.BronzeCnt, 0) AS BronzeBadges,
        COALESCE(pa.QCount, 0) AS QuestionCount,
        COALESCE(pa.ACount, 0) AS AnswerCount,
        COALESCE(pa.QScoreSum, 0) AS QuestionScoreSum,
        COALESCE(pa.AScoreSum, 0) AS AnswerScoreSum,
        COALESCE(pa.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(pa.LastPostDate, u.CreationDate) AS LastActivity,
        lc.CommentText,
        lc.CommentDate,
        tt.Top3Tags,
        CASE WHEN gad.Id IS NOT NULL THEN 1 ELSE 0 END AS HasGoldAndDupClose
    FROM Users u
    LEFT JOIN BadgeCounts bc ON bc.UserId = u.Id
    LEFT JOIN PostAgg pa ON pa.UserId = u.Id
    LEFT JOIN (SELECT * FROM LatestComment WHERE rn = 1) lc ON lc.UserId = u.Id
    LEFT JOIN TopTags tt ON tt.UserId = u.Id
    LEFT JOIN GoldAndDupClose gad ON gad.Id = u.Id
),
RankedUsers AS (
    SELECT
        uc.UserId,
        uc.DisplayName,
        uc.Reputation,
        uc.GoldBadges,
        uc.SilverBadges,
        uc.BronzeBadges,
        uc.QuestionCount,
        uc.AnswerCount,
        uc.QuestionScoreSum,
        uc.AnswerScoreSum,
        uc.AvgAnswerScore,
        uc.LastActivity,
        uc.CommentText,
        uc.CommentDate,
        uc.Top3Tags,
        uc.HasGoldAndDupClose,
        ROW_NUMBER() OVER (ORDER BY
            (uc.Reputation * 0.4
             + uc.QuestionCount * 0.2
             + uc.AnswerCount * 0.3
             + uc.GoldBadges * 5
             + uc.SilverBadges * 2
             + uc.BronzeBadges) DESC) AS ActivityRank,
        PERCENT_RANK() OVER (ORDER BY uc.Reputation) AS RepPercentile
    FROM UserCombined uc
)
SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.AvgAnswerScore,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.Top3Tags,
    ru.HasGoldAndDupClose,
    ru.ActivityRank,
    ru.RepPercentile,
    COALESCE(ru.CommentText, '<no recent comment>') AS RecentComment,
    CASE WHEN ru.CommentDate IS NULL THEN NULL ELSE ru.CommentDate END AS RecentCommentDate
FROM RankedUsers ru
WHERE ru.ActivityRank <= 500
UNION ALL
SELECT
    NULL AS UserId,
    'SUMMARY' AS DisplayName,
    SUM(r.Reputation) AS Reputation,
    SUM(r.QuestionCount) AS QuestionCount,
    SUM(r.AnswerCount) AS AnswerCount,
    AVG(r.AvgAnswerScore) AS AvgAnswerScore,
    SUM(r.GoldBadges) AS GoldBadges,
    SUM(r.SilverBadges) AS SilverBadges,
    SUM(r.BronzeBadges) AS BronzeBadges,
    NULL AS Top3Tags,
    SUM(r.HasGoldAndDupClose) AS HasGoldAndDupClose,
    NULL AS ActivityRank,
    NULL AS RepPercentile,
    NULL AS RecentComment,
    NULL AS RecentCommentDate
FROM RankedUsers r
WHERE r.ActivityRank <= 500
ORDER BY ActivityRank;