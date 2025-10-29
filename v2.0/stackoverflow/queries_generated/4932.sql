-- {"query": "4932.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2165} 

WITH UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS PostCount
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
RankedUserPosts AS (
    SELECT
        p.OwnerUserId,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.CreationDate AS PostCreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        CASE
            WHEN pt.Name = 'Question' THEN 'Q'
            WHEN pt.Name = 'Answer' THEN 'A'
            ELSE 'O'
        END AS PostTypeShort
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
),
RecentUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        MAX(p.PostCreationDate) AS LastPostDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViewCount,
        SUM(p.FavoriteCount) AS TotalFavoriteCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id <= 10000 -- Limit to a subset of users for performance
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
UserEngagement AS (
    SELECT
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.UserCreationDate,
        ru.LastPostDate,
        ru.QuestionCount,
        ru.AnswerCount,
        ru.TotalScore,
        ru.TotalViewCount,
        ru.TotalFavoriteCount,
        ru.GoldBadges,
        ru.SilverBadges,
        ru.BronzeBadges,
        AVG(p.Score) OVER (PARTITION BY ru.UserId) AS AvgPostScore,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount, -- VoteTypeId 2 is UpMod
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount -- VoteTypeId 3 is DownMod
    FROM RecentUserActivity ru
    LEFT JOIN Comments c ON ru.UserId = c.UserId
    LEFT JOIN Votes v ON ru.UserId = v.UserId AND v.VoteTypeId IN (2, 3)
    GROUP BY ru.UserId, ru.DisplayName, ru.Reputation, ru.UserCreationDate, ru.LastPostDate, ru.QuestionCount, ru.AnswerCount, ru.TotalScore, ru.TotalViewCount, ru.TotalFavoriteCount, ru.GoldBadges, ru.SilverBadges, ru.BronzeBadges
),
PostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate AS PostCreationDate,
        p.ClosedDate,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        LEN(p.Title) AS TitleLength,
        LEN(p.Tags) AS TagsLength,
        p.AnswerCount,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount, -- LinkTypeId 3 is Duplicate
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 5) AS EditBodyCount -- PostHistoryTypeId 5 is Edit Body
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.PostTypeId IN (1, 2) -- Questions and Answers only
),
ComplexMetrics AS (
    SELECT
        pm.PostId,
        pm.OwnerUserId,
        pm.PostTypeName,
        pm.Score,
        pm.ViewCount,
        pm.CommentCount,
        pm.FavoriteCount,
        pm.PostCreationDate,
        pm.IsClosed,
        pm.TitleLength,
        pm.TagsLength,
        pm.AnswerCount,
        pm.DuplicateLinkCount,
        pm.EditBodyCount,
        ue.Reputation AS OwnerReputation,
        ue.GoldBadges AS OwnerGoldBadges,
        ue.SilverBadges AS OwnerSilverBadges,
        ue.BronzeBadges AS OwnerBronzeBadges,
        ue.QuestionCount AS OwnerQuestionCount,
        ue.AnswerCount AS OwnerAnswerCount,
        ue.UpVoteCount AS OwnerUpVoteCount,
        ue.DownVoteCount AS OwnerDownVoteCount,
        CASE
            WHEN pm.Score > 0 AND pm.ViewCount > 0 THEN CAST(pm.Score AS REAL) / pm.ViewCount
            ELSE 0
        END AS ScoreToViewRatio,
        CASE
            WHEN pm.PostTypeName = 'Question' AND pm.AnswerCount > 0 THEN CAST(pm.Score AS REAL) / pm.AnswerCount
            WHEN pm.PostTypeName = 'Question' AND pm.AnswerCount = 0 THEN pm.Score
            ELSE 0
        END AS ScorePerAnswer,
        DATEDIFF(day, pm.PostCreationDate, GETDATE()) AS DaysSinceCreation,
        ROW_NUMBER() OVER (ORDER BY pm.Score DESC, pm.ViewCount DESC) AS GlobalRank,
        SUM(pm.Score) OVER (ORDER BY pm.PostCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotalScore,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pm.PostId AND c.Score > 0) AS PositiveCommentCount,
        UPPER(SUBSTRING(pm.PostTypeName, 1, 1)) + LOWER(SUBSTRING(pm.PostTypeName, 2, LEN(pm.PostTypeName))) AS FormattedPostTypeName
    FROM PostMetrics pm
    JOIN UserEngagement ue ON pm.OwnerUserId = ue.UserId
    WHERE ue.Reputation > 1000 -- Consider users with some reputation
)
SELECT
    cm.PostId,
    cm.PostTypeName,
    cm.Score,
    cm.ViewCount,
    cm.CommentCount,
    cm.FavoriteCount,
    cm.IsClosed,
    cm.TitleLength,
    cm.TagsLength,
    cm.AnswerCount,
    cm.DuplicateLinkCount,
    cm.EditBodyCount,
    cm.OwnerReputation,
    cm.OwnerGoldBadges,
    cm.OwnerSilverBadges,
    cm.OwnerBronzeBadges,
    cm.OwnerQuestionCount,
    cm.OwnerAnswerCount,
    cm.OwnerUpVoteCount,
    cm.OwnerDownVoteCount,
    cm.ScoreToViewRatio,
    cm.ScorePerAnswer,
    cm.DaysSinceCreation,
    cm.GlobalRank,
    cm.RunningTotalScore,
    cm.PositiveCommentCount,
    cm.FormattedPostTypeName,
    (SELECT COUNT(Id) FROM Posts WHERE OwnerUserId = cm.OwnerUserId AND PostTypeId = 1 AND Score > 50) AS OwnerHighScoringQuestions,
    COALESCE(ue.LastPostDate, '1900-01-01') AS LastActivityNonNull,
    CASE WHEN cm.PostTypeName = 'Question' THEN 'This is a question' WHEN cm.PostTypeName = 'Answer' THEN 'This is an answer' ELSE 'Other' END AS PostTypeDescription,
    CASE WHEN cm.OwnerReputation >= 10000 THEN 'High' WHEN cm.OwnerReputation >= 1000 THEN 'Medium' ELSE 'Low' END AS ReputationTier,
    CASE
        WHEN cm.PostCreationDate BETWEEN DATEADD(day, -7, GETDATE()) AND GETDATE() THEN 'Recent'
        WHEN cm.PostCreationDate BETWEEN DATEADD(day, -30, GETDATE()) AND DATEADD(day, -7, GETDATE()) THEN 'PastMonth'
        ELSE 'Older'
    END AS PostAgeCategory,
    ue.DisplayName AS OwnerDisplayName -- Left join to ensure all complex metrics are returned
FROM ComplexMetrics cm
LEFT JOIN UserEngagement ue ON cm.OwnerUserId = ue.UserId
WHERE cm.Score > 0 OR cm.ViewCount > 100 -- Filter for posts with some activity
ORDER BY cm.GlobalRank;
