-- {"query": "4865.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1157} 
WITH PostInteractions AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        COALESCE(pc.CommentCount, 0) AS TotalComments,
        COALESCE(pv.UpVoteCount, 0) AS TotalUpVotes,
        COALESCE(ph.EditCount, 0) AS TotalEdits,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN pu.Id IS NOT NULL THEN 1 ELSE 0 END AS IsProtected
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) pc ON p.Id = pc.PostId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS UpVoteCount
        FROM Votes
        WHERE VoteTypeId = 2
        GROUP BY PostId
    ) pv ON p.Id = pv.PostId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS EditCount
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4, 5, 6)
        GROUP BY PostId
    ) ph ON p.Id = ph.PostId
    LEFT JOIN (
        SELECT DISTINCT PostId
        FROM PostHistory
        WHERE PostHistoryTypeId = 19
    ) pu ON p.Id = pu.PostId
),
UserPostSummary AS (
    SELECT
        OwnerUserId,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(TotalUpVotes) AS TotalUserUpVotes,
        AVG(TotalComments) AS AvgPostComments,
        MAX(PostCreationDate) AS LastPostDate
    FROM PostInteractions
    WHERE OwnerUserId IS NOT NULL AND OwnerUserId > 0
    GROUP BY OwnerUserId
),
RankedPosts AS (
    SELECT
        pi.PostId,
        pi.OwnerUserId,
        pi.Title,
        pi.TotalUpVotes,
        pi.TotalComments,
        pi.TotalEdits,
        pi.IsClosed,
        pi.IsProtected,
        ROW_NUMBER() OVER (ORDER BY pi.TotalUpVotes DESC, pi.TotalComments DESC) AS RankByEngagement,
        DENSE_RANK() OVER (PARTITION BY pi.PostTypeId ORDER BY pi.TotalEdits DESC) AS RankByEditsPerType,
        LAG(pi.TotalUpVotes, 1, 0) OVER (ORDER BY pi.PostCreationDate) AS PreviousPostUpVotes
    FROM PostInteractions pi
)
SELECT
    u.DisplayName AS UserName,
    COALESCE(ups.QuestionCount, 0) AS QuestionsAsked,
    COALESCE(ups.AnswerCount, 0) AS AnswersProvided,
    COALESCE(u.Reputation, 0) AS UserReputation,
    COALESCE(u.UpVotes, 0) AS UserTotalUpVotes,
    COALESCE(u.DownVotes, 0) AS UserTotalDownVotes,
    COALESCE(ups.TotalUserUpVotes, 0) AS SumOfPostUpVotes,
    rp.Title AS TopEngagingPostTitle,
    rp.TotalUpVotes AS TopPostUpVotes,
    rp.TotalComments AS TopPostComments,
    rp.TotalEdits AS TopPostEdits,
    rp.RankByEngagement AS PostEngagementRank,
    rp.RankByEditsPerType AS PostEditRankForType,
    rp.PreviousPostUpVotes AS PreviousPostUpVotesCount,
    CASE
        WHEN ups.QuestionCount > 1000 AND ups.AnswerCount > 1000 THEN 'Highly Prolific'
        WHEN ups.QuestionCount > 500 OR ups.AnswerCount > 500 THEN 'Prolific Contributor'
        ELSE 'Standard Contributor'
    END AS ContributorLevel,
    CASE
        WHEN rp.IsClosed = 1 AND rp.IsProtected = 0 THEN 'Closed'
        WHEN rp.IsClosed = 0 AND rp.IsProtected = 1 THEN 'Protected'
        WHEN rp.IsClosed = 1 AND rp.IsProtected = 1 THEN 'Protected & Closed'
        ELSE 'Open'
    END AS PostStatus,
    RPAD(u.DisplayName, 20, ' ') AS FormattedUserName,
    LENGTH(u.AboutMe) AS AboutMeLength,
    UPPER(SUBSTRING(u.WebsiteUrl FROM '://([^/]+)')) AS DomainNameFromUrl
FROM Users u
JOIN UserPostSummary ups ON u.Id = ups.OwnerUserId
LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId AND rp.RankByEngagement = 1
WHERE u.Reputation > 10000
ORDER BY UserReputation DESC, ups.LastPostDate ASC, rp.TotalUpVotes DESC
LIMIT 100;