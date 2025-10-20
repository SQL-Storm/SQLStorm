-- {"query": "48065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 976} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN pt.Name = 'Question' THEN p.Id ELSE NULL END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN pt.Name = 'Answer' THEN p.Id ELSE NULL END) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostCreationDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostQuality AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        pt.Name AS PostType,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.AnswerCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
        u.DisplayName AS OwnerDisplayName,
        COUNT(DISTINCT c.Id) AS CommentCountOnPost
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY
        p.Id,
        p.Title,
        p.CreationDate,
        pt.Name,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.AnswerCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        u.DisplayName
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.UserCreationDate,
    ue.TotalPosts,
    ue.QuestionCount,
    ue.AnswerCount,
    ue.UpVotesReceived,
    ue.DownVotesReceived,
    ue.BadgeCount,
    ue.LastPostCreationDate,
    SUM(CASE WHEN pq.PostType = 'Question' THEN pq.Score ELSE 0 END) AS TotalQuestionScore,
    AVG(CASE WHEN pq.PostType = 'Question' THEN pq.ViewCount ELSE NULL END) AS AvgQuestionViewCount,
    SUM(CASE WHEN pq.PostType = 'Question' THEN pq.CommentCountOnPost ELSE 0 END) AS TotalQuestionComments,
    SUM(CASE WHEN pq.PostType = 'Answer' THEN pq.Score ELSE 0 END) AS TotalAnswerScore,
    AVG(CASE WHEN pq.PostType = 'Answer' THEN pq.CommentCountOnPost ELSE NULL END) AS AvgAnswerComments,
    SUM(pq.IsClosed) AS TotalClosedPosts,
    SUM(pq.IsCommunityOwned) AS TotalCommunityOwnedPosts
FROM UserEngagement ue
JOIN PostQuality pq ON ue.UserId = pq.OwnerDisplayName -- Assuming OwnerDisplayName reflects the User's DisplayName for simplicity in this join
GROUP BY
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.UserCreationDate,
    ue.TotalPosts,
    ue.QuestionCount,
    ue.AnswerCount,
    ue.UpVotesReceived,
    ue.DownVotesReceived,
    ue.BadgeCount,
    ue.LastPostCreationDate
ORDER BY ue.Reputation DESC, ue.TotalPosts DESC
LIMIT 1000;
