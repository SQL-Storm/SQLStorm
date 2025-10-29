-- {"query": "2687.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1995} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        1 AS Level,
        t.WikiPostId
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Level + 1,
        t2.WikiPostId
    FROM Tags t2
    INNER JOIN RecursiveTagHierarchy r ON t2.ExcerptPostId = r.WikiPostId
    WHERE r.Level < 3
),
UserActivityScores AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p2.Id) FILTER (WHERE p2.PostTypeId = 2) AS AnswersPosted,
        COALESCE(SUM(v.VoteCount),0) AS TotalVotesReceived,
        COUNT(DISTINCT b.Id) AS BadgesEarned,
        AVG(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p2.Id) DESC NULLS LAST, u.Reputation DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Posts p2 ON p2.OwnerUserId = u.Id
    LEFT JOIN LATERAL (
        SELECT 
            v2.PostId,
            SUM(CASE WHEN v2.VoteTypeId IN (2,1) THEN 1
                     WHEN v2.VoteTypeId = 3 THEN -1 ELSE 0 END) AS VoteCount
        FROM Votes v2
        WHERE v2.PostId = p2.Id
        GROUP BY v2.PostId
    ) v ON v.PostId = p2.Id
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date > (CURRENT_DATE - INTERVAL '1 year')
    GROUP BY u.Id, u.DisplayName
),
QuestionAnswerStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        COALESCE(q.FavoriteCount,0) AS FavoriteCount,
        q.OwnerUserId,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC NULLS LAST) AS AnswerRank,
        EXISTS (
            SELECT 1 
            FROM PostLinks pl 
            WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3
        ) AS HasDuplicateLink
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
FilteredPostsWithCommentsAndEdits AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        c.CommentCount,
        c.LatestCommentDate,
        ph.LatestEditDate,
        ph.EditCount,
        ph.HasRollback
    FROM Posts p
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(*) AS CommentCount,
            MAX(CreationDate) AS LatestCommentDate
        FROM Comments
        GROUP BY PostId
    ) c ON c.PostId = p.Id
    LEFT JOIN (
        SELECT
            PostId,
            MAX(CreationDate) AS LatestEditDate,
            COUNT(*) AS EditCount,
            MAX(CASE WHEN PostHistoryTypeId IN (7,8,9) THEN 1 ELSE 0 END) AS HasRollback
        FROM PostHistory
        GROUP BY PostId
    ) ph ON ph.PostId = p.Id
),
UserTagContribution AS (
    SELECT 
        u.Id AS UserId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) AS TagName,
        COUNT(*) AS PostCount
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY u.Id, TagName
),
TagPopularityRanked AS (
    SELECT
        t.TagName,
        t.Count,
        RANK() OVER (ORDER BY t.Count DESC) AS PopularityRank
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
UsersWithTopTags AS (
    SELECT
        utc.UserId,
        utc.TagName,
        utc.PostCount,
        tpr.PopularityRank
    FROM UserTagContribution utc
    JOIN TagPopularityRanked tpr ON utc.TagName = tpr.TagName
    WHERE tpr.PopularityRank <= 50
),
UserBestAnswerPerformance AS (
    SELECT
        u.Id AS UserId,
        COUNT(a.Id) FILTER (
            WHERE a.Score >= 5 
              AND a.OwnerUserId = u.Id
              AND a.AcceptedAnswerId = a.Id
        ) AS HighScoreAcceptedAnswers,
        COUNT(a.Id) FILTER (
            WHERE a.Score < 5 
              AND a.OwnerUserId = u.Id
              AND a.AcceptedAnswerId = a.Id
        ) AS LowScoreAcceptedAnswers
    FROM Users u
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2 AND a.AcceptedAnswerId = a.Id
    GROUP BY u.Id
),
FinalCombinedStats AS (
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.QuestionsPosted,
        uas.AnswersPosted,
        uas.TotalVotesReceived,
        uas.BadgesEarned,
        uas.AvgPostScore,
        uas.LastPostDate,
        uas.ActivityRank,
        COALESCE(ubbp.HighScoreAcceptedAnswers,0) AS HighScoreAcceptedAnswers,
        COALESCE(ubbp.LowScoreAcceptedAnswers,0) AS LowScoreAcceptedAnswers,
        COALESCE(tut.TagName, 'No Top Tag') AS TopTag,
        tut.PostCount AS PostsForTopTag,
        tut.PopularityRank AS TopTagPopularityRank
    FROM UserActivityScores uas
    LEFT JOIN UserBestAnswerPerformance ubbp ON uas.UserId = ubbp.UserId
    LEFT JOIN UsersWithTopTags tut ON uas.UserId = tut.UserId
    WHERE uas.AnswersPosted >= 5
),
TopContributorsWithDuplicates AS (
    SELECT
        fcs.*,
        qa.HasDuplicateLink
    FROM FinalCombinedStats fcs
    JOIN QuestionAnswerStats qa ON qa.OwnerUserId = fcs.UserId
    WHERE qa.HasDuplicateLink = TRUE
)
SELECT
    fcs.UserId,
    fcs.DisplayName,
    fcs.QuestionsPosted,
    fcs.AnswersPosted,
    fcs.TotalVotesReceived,
    fcs.BadgesEarned,
    ROUND(fcs.AvgPostScore::numeric,2) AS AveragePostScore,
    fcs.LastPostDate,
    fcs.ActivityRank,
    fcs.HighScoreAcceptedAnswers,
    fcs.LowScoreAcceptedAnswers,
    fcs.TopTag,
    fcs.PostsForTopTag,
    fcs.TopTagPopularityRank,
    COUNT(DISTINCT p.Id) FILTER (
        WHERE p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%'
    ) AS PostsWithSpecificTags,
    COUNT(DISTINCT c.Id) AS TotalCommentsMade,
    STRING_AGG(DISTINCT nt.Name, ', ') FILTER (WHERE nt.Id IS NOT NULL) AS BadgeClassesEarned,
    MAX(ph.CreationDate) FILTER (
        WHERE ph.PostHistoryTypeId = 10
    ) AS MostRecentCloseVoteDate,
    MIN(ph.CreationDate) FILTER (
        WHERE ph.PostHistoryTypeId = 11
    ) AS EarliestReopenVoteDate,
    COUNT(pl.Id) FILTER (
        WHERE pl.LinkTypeId = 1
    ) AS TotalLinkedPosts
FROM FinalCombinedStats fcs
LEFT JOIN Posts p ON p.OwnerUserId = fcs.UserId
LEFT JOIN Comments c ON c.UserId = fcs.UserId
LEFT JOIN Badges b ON b.UserId = fcs.UserId
LEFT JOIN PostHistory ph ON ph.UserId = fcs.UserId
LEFT JOIN PostLinks pl ON pl.PostId = p.Id
LEFT JOIN PostHistoryTypes nt ON nt.Id = b.Class
WHERE fcs.ActivityRank <= 100
GROUP BY
    fcs.UserId,
    fcs.DisplayName,
    fcs.QuestionsPosted,
    fcs.AnswersPosted,
    fcs.TotalVotesReceived,
    fcs.BadgesEarned,
    fcs.AvgPostScore,
    fcs.LastPostDate,
    fcs.ActivityRank,
    fcs.HighScoreAcceptedAnswers,
    fcs.LowScoreAcceptedAnswers,
    fcs.TopTag,
    fcs.PostsForTopTag,
    fcs.TopTagPopularityRank
ORDER BY fcs.ActivityRank
LIMIT 20;
