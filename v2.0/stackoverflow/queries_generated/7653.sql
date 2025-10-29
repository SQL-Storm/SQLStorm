-- {"query": "7653.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2399} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalViews,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS ReputationRank,
        RANK() OVER (ORDER BY u.ViewCount DESC, u.Id) AS ViewRank,
        DENSE_RANK() OVER (ORDER BY u.UpVotes DESC, u.Id) AS UpvoteRank,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Veteran'
            WHEN u.Reputation >= 100 THEN 'Member'
            ELSE 'Newbie'
        END AS ReputationLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount, u.UpVotes, u.DownVotes, u.CreationDate
),
TopQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        STRING_AGG(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ', ') AS TagList,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS QuestionStatus,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 
      AND p.CreationDate >= '2019-01-01'
      AND p.Score > 10
      AND p.ViewCount > 100
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.CreationDate, p.OwnerUserId, u.DisplayName, p.Tags, p.ClosedDate, p.CommunityOwnedDate
),
PostAnalysis AS (
    SELECT 
        t.Id AS PostId,
        t.PostTypeId,
        t.Title,
        t.Body,
        t.Score,
        t.ViewCount,
        t.AnswerCount,
        t.CommentCount,
        t.CreationDate,
        t.OwnerUserId,
        t.ParentId,
        CASE WHEN t.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = t.Id AND v.VoteTypeId = 2), 
            0
        ) AS UpvoteCount,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = t.Id AND v.VoteTypeId = 3), 
            0
        ) AS DownvoteCount,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = t.Id), 
            0
        ) AS CommentCountActual,
        CASE 
            WHEN t.Score > 5 THEN 'High'
            WHEN t.Score > 0 THEN 'Medium'
            WHEN t.Score = 0 THEN 'Low'
            ELSE 'Negative'
        END AS ScoreCategory,
        DATEDIFF(day, t.CreationDate, GETDATE()) AS DaysSinceCreation,
        CASE 
            WHEN DATEDIFF(day, t.CreationDate, GETDATE()) > 365 THEN 'Old'
            WHEN DATEDIFF(day, t.CreationDate, GETDATE()) > 30 THEN 'Recent'
            WHEN DATEDIFF(day, t.CreationDate, GETDATE()) > 7 THEN 'Week'
            ELSE 'Daily'
        END AS TimeRange,
        CASE 
            WHEN t.Body LIKE '%<code>%' THEN 1
            ELSE 0
        END AS ContainsCode,
        REVERSE(SUBSTRING(REVERSE(t.Title), 1, CHARINDEX(' ', REVERSE(t.Title)) - 1)) AS TitleLastWord,
        LEFT(t.Title, 50) AS ShortTitle
    FROM Posts t
    WHERE t.CreationDate BETWEEN '2019-01-01' AND '2023-12-31'
      AND t.PostTypeId IN (1, 2)
),
DetailedUserAnalysis AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.PostCount,
        us.CommentCount,
        us.BadgeCount,
        us.TotalPostScore,
        us.TotalViews,
        us.AvgPostScore,
        us.ReputationLevel,
        us.ReputationRank,
        us.ViewRank,
        COALESCE((SELECT SUM(p.Score) 
                  FROM Posts p 
                  WHERE p.OwnerUserId = us.UserId 
                    AND p.PostTypeId = 1 
                    AND p.CreationDate >= '2020-01-01'), 
                 0) AS RecentQuestionScore,
        COALESCE((SELECT COUNT(*)
                  FROM Posts p 
                  WHERE p.OwnerUserId = us.UserId 
                    AND p.PostTypeId = 1 
                    AND p.CreationDate >= '2020-01-01'), 
                 0) AS RecentQuestionCount,
        COALESCE((SELECT AVG(p.Score)
                  FROM Posts p 
                  WHERE p.OwnerUserId = us.UserId 
                    AND p.PostTypeId = 2 
                    AND p.CreationDate >= '2020-01-01'), 
                 0) AS RecentAnswerScore,
        COALESCE((SELECT COUNT(*)
                  FROM Posts p 
                  WHERE p.OwnerUserId = us.UserId 
                    AND p.PostTypeId = 2 
                    AND p.CreationDate >= '2020-01-01'), 
                 0) AS RecentAnswerCount,
        CASE 
            WHEN us.BadgeCount > 50 THEN 'Veteran'
            WHEN us.BadgeCount > 20 THEN 'Regular'
            WHEN us.BadgeCount > 5 THEN 'Active'
            ELSE 'Beginner'
        END AS ActivityLevel,
        (us.UpVotes + 1) / (CAST(us.DownVotes + 1 AS FLOAT)) AS UpVoteDownVoteRatio
    FROM UserStats us
    WHERE us.PostCount > 20
),
CombinedData AS (
    SELECT 
        dua.UserId,
        dua.DisplayName,
        dua.Reputation,
        dua.PostCount,
        dua.CommentCount,
        dua.BadgeCount,
        dua.TotalPostScore,
        dua.TotalViews,
        dua.AvgPostScore,
        dua.ReputationLevel,
        dua.ReputationRank,
        dua.ViewRank,
        dua.RecentQuestionScore,
        dua.RecentQuestionCount,
        dua.RecentAnswerScore,
        dua.RecentAnswerCount,
        dua.ActivityLevel,
        dua.UpVoteDownVoteRatio,
        ROW_NUMBER() OVER (ORDER BY dua.Reputation DESC, dua.PostCount DESC) AS OverallRank,
        RANK() OVER (ORDER BY dua.RecentQuestionScore DESC, dua.RecentQuestionCount DESC) AS RecentQuestionRank,
        DENSE_RANK() OVER (ORDER BY dua.RecentAnswerScore DESC, dua.RecentAnswerCount DESC) AS RecentAnswerRank
    FROM DetailedUserAnalysis dua
    WHERE dua.Reputation > 1000
)
SELECT 
    cd.UserId,
    cd.DisplayName,
    cd.Reputation,
    cd.PostCount,
    cd.CommentCount,
    cd.BadgeCount,
    cd.TotalPostScore,
    cd.TotalViews,
    cd.AvgPostScore,
    cd.ReputationLevel,
    cd.ReputationRank,
    cd.ViewRank,
    cd.RecentQuestionScore,
    cd.RecentQuestionCount,
    cd.RecentAnswerScore,
    cd.RecentAnswerCount,
    cd.ActivityLevel,
    cd.UpVoteDownVoteRatio,
    cd.OverallRank,
    cd.RecentQuestionRank,
    cd.RecentAnswerRank,
    COALESCE(
        (SELECT COUNT(DISTINCT ph.PostId)
         FROM PostHistory ph
         WHERE ph.UserId = cd.UserId 
           AND ph.CreationDate > '2022-01-01'
           AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9)), 
        0
    ) AS EditCount,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = cd.UserId AND p.PostTypeId = 1 AND p.Score > 5000) 
        THEN 'High Performer'
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = cd.UserId AND p.PostTypeId = 1 AND p.Score > 1000) 
        THEN 'Moderate Performer'
        ELSE 'Regular Performer'
    END AS PerformanceTier,
    IIF(cd.ReputationLevel = 'Elite', 'True', 'False') AS IsElite,
    CONCAT('User-', cd.UserId, '-', cd.ReputationLevel) AS UserIdentifier,
    DATEDIFF(year, (SELECT MIN(CreationDate) FROM Users), GETDATE()) AS DatabaseAge,
    DATEDIFF(day, cd.ReputationRank, cd.ViewRank) AS RankDifference,
    CASE 
        WHEN cd.BadgeCount > 50 
        THEN 'Heavy Badge Holder' 
        ELSE 'Moderate Badge Holder' 
    END AS BadgeClassification
FROM CombinedData cd
WHERE cd.PostCount >= 50 
  AND cd.CommentsCount >= 20 
  AND.cd.Reputation > 10000
GROUP BY 
    cd.UserId, cd.DisplayName, cd.Reputation, cd.PostCount, cd.CommentCount, 
    cd.BadgeCount, cd.TotalPostScore, cd.TotalViews, cd.AvgPostScore, 
    cd.ReputationLevel, cd.ReputationRank, cd.ViewRank, cd.RecentQuestionScore, 
    cd.RecentQuestionCount, cd.RecentAnswerScore, cd.RecentAnswerCount, 
    cd.ActivityLevel, cd.UpVoteDownVoteRatio, cd.OverallRank, 
    cd.RecentQuestionRank, cd.RecentAnswerRank
HAVING COUNT(*) > 0
ORDER BY 
    cd.Reputation DESC, 
    cd.PostCount DESC,
    cd.TotalPostScore DESC
OFFSET 100 ROWS FETCH NEXT 200 ROWS ONLY;