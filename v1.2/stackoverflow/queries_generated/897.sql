-- {"query": "897.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1636} 

WITH RecursiveUserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, b.Class

    UNION ALL

    SELECT 
        r.UserId,
        r.DisplayName,
        r.Class,
        r.BadgeCount + 1
    FROM RecursiveUserBadgeCounts r
    WHERE r.BadgeCount < 3
),
TopUsers AS (
    SELECT DISTINCT UserId, DisplayName
    FROM RecursiveUserBadgeCounts
    WHERE BadgeCount >= 2
),
QuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        STRING_AGG(DISTINCT tag, ',' ORDER BY tag) AS TagList,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS UserRankByScore
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) AS tag
    ) AS tags ON TRUE
    WHERE p.PostTypeId = 1 -- questions only
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount
),
RecentEdits AS (
    SELECT 
        ph.PostId,
        MAX(ph.CreationDate) AS LastEditDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) AS EditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseVotes,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 END) AS ReopenVotes
    FROM PostHistory ph
    GROUP BY ph.PostId
),
AnswerStats AS (
    SELECT 
        ans.ParentId AS QuestionId,
        COUNT(ans.Id) AS TotalAnswers,
        AVG(ans.Score) AS AvgAnswerScore,
        MAX(ans.Score) AS MaxAnswerScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM Posts ans
    LEFT JOIN Votes v ON ans.Id = v.PostId
    WHERE ans.PostTypeId = 2 -- answers only
    GROUP BY ans.ParentId
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        COUNT(*) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS PostsLast30Days,
        RANK() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS RecentPostRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= NOW() - INTERVAL '90 days'
),
DuplicateLinks AS (
    SELECT DISTINCT pl.PostId, pl.RelatedPostId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3 -- Duplicate link type
),
CombinedQuestions AS (
    SELECT 
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.TagList,
        COALESCE(a.TotalAnswers, 0) AS TotalAnswersFromAnswers,
        COALESCE(a.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(a.MaxAnswerScore, 0) AS MaxAnswerScore,
        COALESCE(a.TotalUpVotes, 0) AS TotalAnswerUpVotes,
        COALESCE(a.TotalDownVotes, 0) AS TotalAnswerDownVotes,
        COALESCE(r.EditCount, 0) AS EditCount,
        COALESCE(r.CloseVotes, 0) AS CloseVotes,
        COALESCE(r.ReopenVotes, 0) AS ReopenVotes,
        CASE WHEN d.PostId IS NOT NULL THEN TRUE ELSE FALSE END AS IsMarkedDuplicate,
        q.UserRankByScore
    FROM QuestionStats q
    LEFT JOIN AnswerStats a ON q.QuestionId = a.QuestionId
    LEFT JOIN RecentEdits r ON q.QuestionId = r.PostId
    LEFT JOIN DuplicateLinks d ON q.QuestionId = d.PostId
),
FinalSelection AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        cu.QuestionId,
        cu.Title,
        cu.CreationDate,
        cu.Score,
        cu.ViewCount,
        cu.AnswerCount,
        cu.CommentCount,
        cu.TagList,
        cu.TotalAnswersFromAnswers,
        cu.AvgAnswerScore,
        cu.MaxAnswerScore,
        cu.TotalAnswerUpVotes,
        cu.TotalAnswerDownVotes,
        cu.EditCount,
        cu.CloseVotes,
        cu.ReopenVotes,
        cu.IsMarkedDuplicate,
        ua.PostsLast30Days,
        RANK() OVER (PARTITION BY u.Id ORDER BY cu.Score DESC, cu.ViewCount DESC) AS UserQuestionRank
    FROM Users u
    INNER JOIN CombinedQuestions cu ON u.Id = cu.OwnerUserId
    LEFT JOIN UserActivityWindow ua ON u.Id = ua.UserId
    WHERE u.Reputation > 1000
      AND cu.UserRankByScore <= 5
      AND (cu.CloseVotes = 0 OR cu.ReopenVotes > cu.CloseVotes)
      AND cu.IsMarkedDuplicate = FALSE
)
SELECT DISTINCT
    fs.UserId,
    fs.DisplayName,
    fs.QuestionId,
    fs.Title,
    fs.CreationDate,
    fs.Score,
    fs.ViewCount,
    fs.AnswerCount,
    fs.CommentCount,
    fs.TagList,
    fs.TotalAnswersFromAnswers,
    fs.AvgAnswerScore,
    fs.MaxAnswerScore,
    fs.TotalAnswerUpVotes,
    fs.TotalAnswerDownVotes,
    fs.EditCount,
    fs.CloseVotes,
    fs.ReopenVotes,
    fs.PostsLast30Days,
    CONCAT(
        'User ', COALESCE(fs.DisplayName, 'UNKNOWN'), 
        ' posted question "', COALESCE(fs.Title, 'NO TITLE'), 
        '" with score ', COALESCE(fs.Score::text, '0'), 
        ', viewed ', COALESCE(fs.ViewCount::text, '0'), ' times, ',
        'tags: ', COALESCE(fs.TagList, 'none'),
        '. Answers count: ', COALESCE(fs.AnswerCount::text, '0'),
        ', average answer score: ', ROUND(fs.AvgAnswerScore::numeric, 2)::text,
        ', max answer score: ', fs.MaxAnswerScore::text,
        '. Edits: ', fs.EditCount::text,
        ', CloseVotes: ', fs.CloseVotes::text,
        ', ReopenVotes: ', fs.ReopenVotes::text,
        ', Posts last 30 days: ', COALESCE(fs.PostsLast30Days::text, '0')
    ) AS Summary
FROM FinalSelection fs
WHERE fs.UserQuestionRank <= 3
ORDER BY fs.UserId, fs.UserQuestionRank;
