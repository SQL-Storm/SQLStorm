-- {"query": "4629.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 700} 
WITH UserContribution AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN c.UserId = u.Id THEN 1 ELSE 0 END) AS CommentCount,
        SUM(CASE WHEN v.UserId = u.Id AND v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.UserId = u.Id AND v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate >= '2010-01-01' AND u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        pt.Name AS PostType,
        COUNT(DISTINCT pc.Id) AS CommentCount,
        COUNT(DISTINCT pv.Id) AS VoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) as rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments pc ON p.Id = pc.PostId
    LEFT JOIN Votes pv ON p.Id = pv.PostId
    WHERE p.CreationDate >= '2015-01-01'
    GROUP BY p.Id, p.Title, p.CreationDate, pt.Name
),
RankedEngagement AS (
    SELECT
        pe.PostId,
        pe.Title,
        pe.PostType,
        pe.CommentCount,
        pe.VoteCount,
        RANK() OVER (ORDER BY pe.VoteCount DESC, pe.CommentCount DESC) AS EngagementRank
    FROM PostEngagement pe
    WHERE pe.rn = 1
)
SELECT
    uc.DisplayName,
    uc.QuestionCount,
    uc.AnswerCount,
    uc.CommentCount AS UserCommentCount,
    uc.UpVoteCount AS UserUpVotes,
    uc.DownVoteCount AS UserDownVotes,
    re.Title AS TopEngagedPostTitle,
    re.PostType AS TopEngagedPostType,
    re.CommentCount AS TopEngagedPostComments,
    re.VoteCount AS TopEngagedPostVotes,
    re.EngagementRank
FROM UserContribution uc
LEFT JOIN RankedEngagement re
    ON uc.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = re.PostId)
WHERE uc.QuestionCount > 10 OR uc.AnswerCount > 20
ORDER BY uc.DisplayName, re.EngagementRank;