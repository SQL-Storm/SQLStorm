-- {"query": "53095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 846} 
WITH ExplodedTags AS (
    SELECT 
        p.Id AS QuestionId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= '2010-01-01'
        AND p.Score > 0
),
TagStats AS (
    SELECT 
        et.TagName,
        COUNT(DISTINCT et.QuestionId) AS QuestionCount,
        AVG(p.ViewCount) AS AvgViews,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswersCount
    FROM ExplodedTags et
    JOIN Posts p ON et.QuestionId = p.Id
    GROUP BY et.TagName
    HAVING COUNT(DISTINCT et.QuestionId) > 1000
),
UserAnswerStats AS (
    SELECT 
        a.OwnerUserId,
        et.TagName,
        COUNT(a.Id) AS AnswerCount,
        SUM(a.Score) AS TotalScore,
        MAX(a.Score) AS MaxScore,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 9) AS TotalBountyEarned
    FROM Posts a
    JOIN ExplodedTags et ON a.ParentId = et.QuestionId
    JOIN Comments c ON c.PostId = a.Id
    JOIN Votes v ON v.PostId = a.Id
    WHERE a.PostTypeId = 2
        AND a.CreationDate >= '2010-01-01'
        AND v.CreationDate >= a.CreationDate
    GROUP BY a.OwnerUserId, et.TagName
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        t.TagName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    JOIN Tags t ON b.Name = t.TagName AND b.TagBased = TRUE
    WHERE b.Date >= '2010-01-01'
    GROUP BY b.UserId, t.TagName
),
RankedUsersPerTag AS (
    SELECT 
        uas.TagName,
        uas.OwnerUserId AS UserId,
        u.DisplayName,
        u.Reputation,
        uas.AnswerCount,
        uas.TotalScore,
        uas.MaxScore,
        uas.CommentCount,
        uas.TotalBountyEarned,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
        ts.QuestionCount,
        ts.AvgViews,
        ts.AcceptedAnswersCount,
        ROW_NUMBER() OVER (PARTITION BY uas.TagName ORDER BY uas.TotalScore DESC, uas.AnswerCount DESC) AS Rank
    FROM UserAnswerStats uas
    JOIN Users u ON uas.OwnerUserId = u.Id
    JOIN TagStats ts ON uas.TagName = ts.TagName
    LEFT JOIN UserBadgeStats ubs ON uas.OwnerUserId = ubs.UserId AND uas.TagName = ubs.TagName
    WHERE u.Reputation > 1000
        AND uas.AnswerCount > 10
)
SELECT 
    TagName,
    UserId,
    DisplayName,
    Reputation,
    AnswerCount,
    TotalScore,
    MaxScore,
    CommentCount,
    TotalBountyEarned,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    QuestionCount,
    AvgViews,
    AcceptedAnswersCount,
    Rank
FROM RankedUsersPerTag
WHERE Rank <= 5
ORDER BY TagName, Rank;