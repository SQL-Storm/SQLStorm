WITH 
TagQuestions AS (
    SELECT 
        p.Id               AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        UNNEST(
            STRING_TO_ARRAY(
                SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags)-2)), 
                '><'
            )
        )                  AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TagStats AS (
    SELECT 
        tq.Tag,
        COUNT(*)                               AS QuestionCount,
        AVG(tq.Score)                          AS AvgQuestionScore,
        MAX(tq.ViewCount)                      AS MaxViews,
        SUM(CASE WHEN tq.Score IS NULL THEN 1 ELSE 0 END) AS NullScoreCount
    FROM TagQuestions tq
    GROUP BY tq.Tag
),
TopTags AS (
    SELECT 
        ts.Tag,
        ts.QuestionCount,
        ts.AvgQuestionScore,
        ts.MaxViews,
        ROW_NUMBER() OVER (ORDER BY ts.QuestionCount DESC) AS TagRank
    FROM TagStats ts
    WHERE ts.QuestionCount > 100
),
UserAnswers AS (
    SELECT 
        a.OwnerUserId                     AS UserId,
        tq.Tag,
        COUNT(*)                          AS AnswerCount,
        AVG(a.Score)                      AS AvgAnswerScore,
        MAX(a.CreationDate)               AS LastAnswerDate
    FROM Posts a
    JOIN TagQuestions tq ON tq.QuestionId = a.ParentId
    WHERE a.PostTypeId = 2
      AND a.OwnerUserId IS NOT NULL
    GROUP BY a.OwnerUserId, tq.Tag
),
UserRankings AS (
    SELECT 
        ua.UserId,
        ua.Tag,
        ua.AnswerCount,
        ua.AvgAnswerScore,
        ROW_NUMBER() OVER (
            PARTITION BY ua.Tag 
            ORDER BY ua.AnswerCount DESC, ua.AvgAnswerScore DESC
        )                                 AS RankInTag
    FROM UserAnswers ua
),
UserBadgeInfo AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserReputation AS (
    SELECT 
        u.Id            AS UserId,
        COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
        u.Reputation,
        COALESCE(ubi.GoldBadges,   0)   AS GoldBadges,
        COALESCE(ubi.SilverBadges, 0)   AS SilverBadges,
        COALESCE(ubi.BronzeBadges, 0)   AS BronzeBadges
    FROM Users u
    LEFT JOIN UserBadgeInfo ubi ON ubi.UserId = u.Id
),
UserVoteTotals AS (
    SELECT 
        u.Id AS UserId,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.UserId = u.Id 
           AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.UserId = u.Id 
           AND v.VoteTypeId = 3) AS DownVoteCount
    FROM Users u
),
ActiveTagContributors AS (
    SELECT 
        tt.Tag,
        tt.QuestionCount,
        tt.AvgQuestionScore,
        tt.MaxViews,
        ur.UserId,
        ur.DisplayName,
        ur.Reputation,
        ur.GoldBadges,
        ur.SilverBadges,
        ur.BronzeBadges,
        uv.UpVoteCount,
        uv.DownVoteCount,
        urk.AnswerCount,
        urk.AvgAnswerScore,
        urk.RankInTag
    FROM TopTags tt
    LEFT JOIN UserRankings urk 
           ON urk.Tag = tt.Tag 
          AND urk.RankInTag <= 3
    LEFT JOIN UserReputation ur 
           ON ur.UserId = urk.UserId
    LEFT JOIN UserVoteTotals uv 
           ON uv.UserId = urk.UserId
    WHERE tt.TagRank <= 10
),
TagWithoutAnswers AS (
    SELECT 
        ts.Tag,
        ts.QuestionCount,
        ts.AvgQuestionScore,
        ts.MaxViews,
        CAST(NULL AS bigint) AS UserId,
        CAST(NULL AS text) AS DisplayName,
        CAST(NULL AS integer) AS Reputation,
        CAST(NULL AS integer) AS GoldBadges,
        CAST(NULL AS integer) AS SilverBadges,
        CAST(NULL AS integer) AS BronzeBadges,
        0    AS UpVoteCount,
        0    AS DownVoteCount,
        0    AS AnswerCount,
        CAST(NULL AS numeric) AS AvgAnswerScore,
        CAST(NULL AS integer) AS RankInTag
    FROM TagStats ts
    WHERE NOT EXISTS (
        SELECT 1 
        FROM TagQuestions tq
        JOIN Posts a ON a.ParentId = tq.QuestionId 
                     AND a.PostTypeId = 2
        WHERE tq.Tag = ts.Tag
    )
)
SELECT *
FROM ActiveTagContributors
UNION ALL
SELECT *
FROM TagWithoutAnswers
ORDER BY Tag, RankInTag NULLS LAST;