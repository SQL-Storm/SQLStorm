-- {"query": "1333.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1850} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        0 AS Level,
        ARRAY[t.TagName] AS Ancestors
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        c.Id,
        c.TagName,
        p.Level + 1,
        p.Ancestors || c.TagName
    FROM Tags c
    JOIN PostLinks pl ON pl.PostId = c.WikiPostId
    JOIN RecursiveTagHierarchy p ON pl.RelatedPostId = p.Id
    WHERE c.IsRequired = 1 AND NOT c.TagName = ANY(p.Ancestors)
),
AggregatedUserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p2.Id) FILTER (WHERE p2.PostTypeId = 2) AS AnswersProvided,
        COALESCE(SUM(vup.VotesUp),0) AS TotalUpVotesReceived,
        COALESCE(SUM(vdown.VotesDown),0) AS TotalDownVotesReceived,
        COUNT(DISTINCT b.Id) AS BadgesCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1 OR p.PostTypeId = 2) AS AvgPostScore,
        MAX(p.CreationDate) AS LastContributionDate,
        MIN(u.CreationDate) AS JoinDate,
        -- Advanced NULL logic with CASE and COALESCE for described reputation rank
        CASE
            WHEN u.Reputation > 100000 THEN 'Legendary'
            WHEN u.Reputation > 20000 THEN 'Expert'
            WHEN u.Reputation > 5000 THEN 'Intermediate'
            WHEN u.Reputation > 0 THEN 'Beginner'
            ELSE COALESCE(NULLIF(u.DisplayName, ''),'<Anonymous>') || ' (no rep)' END AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Posts p2 ON p2.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VotesUp FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId
    ) vup ON vup.PostId = ANY(ARRAY(SELECT Id FROM Posts WHERE OwnerUserId = u.Id))
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VotesDown FROM Votes WHERE VoteTypeId = 3 GROUP BY PostId
    ) vdown ON vdown.PostId = ANY(ARRAY(SELECT Id FROM Posts WHERE OwnerUserId = u.Id))
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS UserTopPostRank,
        RANK() OVER (ORDER BY p.Score DESC) AS GlobalScoreRank,
        COUNT(*) OVER (PARTITION BY p.Tags) AS PostsPerTagCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Score IS NOT NULL
),
PostWithVotingPerformance AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId=2) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId=3) AS DownVotes,
        SUM(COALESCE(v.BountyAmount,0)) AS TotalBounty,
        -- Calculate engagement score using complex expressions and precedence
        (COALESCE(NULLIF(p.ViewCount,0),1)::float 
         * (1 + COALESCE(NULLIF(p.Score,0), 0))
         + GREATEST(COALESCE(NULLIF(voteStats.UpVotes,0),0), 0)
         - COALESCE(voteStats.DownVotes, 0)) AS EngagementScore
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN (
        SELECT PostId,
            COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotes,
            COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotes
        FROM Votes
        GROUP BY PostId
    ) voteStats ON voteStats.PostId = p.Id
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, voteStats.UpVotes, voteStats.DownVotes
),
FilteredRecentEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS RecentEditRank
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body or Tags
      AND ph.CreationDate > NOW() - INTERVAL '30 days'
),
ClosedDupeQuestions AS (
    SELECT DISTINCT q.Id, q.Title, q.CreationDate, pl.RelatedPostId AS DuplicateOfQuestionId
    FROM Posts q
    JOIN PostHistory phc ON phc.PostId = q.Id AND phc.PostHistoryTypeId=10 AND phc.Comment ~ 'Duplicate' 
    JOIN PostLinks pl ON pl.PostId = q.Id AND pl.LinkTypeId = 3 -- Duplicate link
    WHERE q.PostTypeId = 1
),
FinalUserInsights AS (
    SELECT
        aus.UserId,
        aus.DisplayName,
        COALESCE(pc.QuestionCount,0) AS ClosedDuplicateQuestions,
        COALESCE(pe.RecentEditCount,0) AS RecentEditsCount,
        aus.QuestionsPosted,
        aus.AnswersProvided,
        aus.TotalUpVotesReceived,
        aus.TotalDownVotesReceived,
        aus.BadgesCount,
        aus.ReputationRank,
        RANK() OVER (ORDER BY aus.TotalUpVotesReceived DESC) AS ReputationUpVoteRank
    FROM AggregatedUserStats aus
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS QuestionCount FROM ClosedDupeQuestions GROUP BY OwnerUserId
    ) pc ON pc.OwnerUserId = aus.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS RecentEditCount FROM FilteredRecentEdits GROUP BY UserId
    ) pe ON pe.UserId = aus.UserId
)
SELECT
    fui.UserId,
    fui.DisplayName,
    fui.ReputationRank,
    fui.BadgesCount,
    fui.QuestionsPosted,
    fui.AnswersProvided,
    fui.TotalUpVotesReceived,
    fui.TotalDownVotesReceived,
    fui.ClosedDuplicateQuestions,
    fui.RecentEditsCount,
    fui.ReputationUpVoteRank,
    rp.Title AS UserTopPostTitle,
    rp.Score AS UserTopPostScore,
    rp.ViewCount AS UserTopPostViews,
    pt.Name AS TopPostTypeName,
    listagg(t.TagName, ', ') WITHIN GROUP (ORDER BY t.TagName) TagsOfTopPost,
    phct.Name AS MostRecentCloseReason,
    EXISTS (
        SELECT 1 FROM RecursiveTagHierarchy rth
        WHERE array_position(rp.Tags, rth.TagName) IS NOT NULL
          AND rth.Level > 1
          AND rth.TagName IS NOT NULL
    ) AS HasHierarchicalRequiredTag
FROM FinalUserInsights fui
LEFT JOIN LATERAL (
    SELECT p.Id, p.Title, p.Score, p.ViewCount, p.Tags, p.PostTypeId
    FROM RankedPosts p
    WHERE p.OwnerUserId = fui.UserId AND p.UserTopPostRank = 1
    LIMIT 1
) rp ON TRUE
LEFT JOIN PostTypes pt ON pt.Id = rp.PostTypeId
LEFT JOIN Tags t ON t.TagName = ANY(rp.Tags)
LEFT JOIN LATERAL (
    SELECT cht.Name
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes cht ON CAST(ph.Comment AS INT) = cht.Id
    WHERE ph.PostId = rp.Id AND ph.PostHistoryTypeId = 10
    ORDER BY ph.CreationDate DESC
    LIMIT 1
) phct ON TRUE
WHERE fui.QuestionsPosted > 10
  AND fui.AnswersProvided > 5
ORDER BY fui.ReputationUpVoteRank
FETCH FIRST 50 ROWS ONLY;
