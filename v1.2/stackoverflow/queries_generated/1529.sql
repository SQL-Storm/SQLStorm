-- {"query": "1529.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1687} 

WITH RecursiveTagDepth(TagId, ParentTagId, Depth) AS (
    SELECT t.Id, NULL::int, 1
    FROM Tags t
    WHERE t.IsRequired = 1
    UNION ALL
    SELECT t.Id, r.TagId, r.Depth + 1
    FROM Tags t
    INNER JOIN RecursiveTagDepth r ON SUBSTRING(t.TagName, 1, LENGTH(r.TagId)::int) = CAST(r.TagId AS text)
    WHERE t.IsRequired = 1
), HighComplexityPostWindows AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        STRING_AGG(DISTINCT b.Name || CASE b.Class WHEN 1 THEN ' 🏅Gold' WHEN 2 THEN ' 🥈Silver' WHEN 3 THEN ' 🥉Bronze' ELSE '' END, ', ') 
          FILTER (WHERE b.Name IS NOT NULL) OVER (PARTITION BY p.OwnerUserId) AS OwnerBadges,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS OwnerBestPostRank,
        LEAD(p.Id) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS NextPostForOwner,
        COALESCE(NULLIF(p.Tags, '')::TEXT[], ARRAY[]::TEXT[]) AS TagsArray,
        array_length(string_to_array(regexp_replace(p.Tags, '<([^>]+)>', '\1'), '>'), 1) as TagCount,
        array_position(string_to_array(COALESCE(p.Tags,''), '><'), 'sql') IS NOT NULL AS ContainsSQLTag,
        (SELECT COUNT(1) FROM Comments c WHERE c.PostId = p.Id AND c.Text ~* 'performance|benchmark|optimiz' AND c.Score >= 2) AS RelevantCommentCount

    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date < p.CreationDate
    WHERE p.PostTypeId IN (1, 2)
), CorrelatedAnswerStats AS (
    SELECT p.Id,
      (SELECT COUNT(1) FROM Posts ans WHERE ans.ParentId = p.Id) AS NumAnswers,
      (SELECT AVG(score) FROM Posts ans WHERE ans.ParentId = p.Id) AS AvgAnswerScore
    FROM Posts p WHERE p.PostTypeId = 1
), LatestHistoryStacked AS (
    SELECT ph.PostId, ph.PostHistoryTypeId, ph.Id, ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13)  -- Close, Reopen, Delete, Undelete etc
), FilteredPostHistories AS (
    SELECT lhs.PostId, lph.Name AS ActionType, lph.Id AS ReasonId, lhs.CreationDate AS ActionDate
    FROM LatestHistoryStacked lhs
    JOIN PostHistoryTypes lph ON lhs.PostHistoryTypeId = lph.Id
    WHERE lhs.rn = 1
), AggregateUserReputationUNTAGS AS (
    SELECT
      u.Id,
      SUM(b.Class)::numeric(10,2) AS SumBadgeClass,
      MAX(u.Reputation) AS MaxReputation,
      COUNT(DISTINCT bt.Id) FILTER (WHERE bt.Name ILIKE '%moderator%' OR bt.Name ILIKE '%expert%') AS SpecialBadgesCount,
      COUNT(DISTINCT bad.Id) FILTER (WHERE bad.TagBased = 1) AS TagBadgesEarned
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Badges bad ON bad.UserId = u.Id
    LEFT JOIN (SELECT Id, Name FROM Badges WHERE Name ILIKE '%moderator%' OR Name ILIKE '%expert%') bt ON bt.Id = bad.Id
    GROUP BY u.Id
), UnionedPostsWithVoteActions AS (
   SELECT PostId, VoteTypeId, CreationDate FROM Votes WHERE VoteTypeId IN (2, 3)  -- Upmod and Downmod
   UNION
   SELECT PostId, VoteTypeId, CreationDate FROM Votes WHERE VoteTypeId = 5      -- Favorite or Saves 
), ComplexUserInfluenceScore AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COALESCE(SUM(COALESCE(p.Score, 0)),0) AS SumPostScores,
        COALESCE(SUM(COALESCE(lp.AvgAnswerScore, 0)),0) AS SumAvgAnswerScores,
        SUM(CASE WHEN EXISTS(
            SELECT 1 FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.Score > 10) THEN 1 ELSE 0 END) AS PostsWithHighScoreAnswers,
        COALESCE(SUM(CASE WHEN up.VoteTypeId = 2 THEN 1 ELSE 0 END), 0)  - 
        COALESCE(SUM(CASE WHEN up.VoteTypeId = 3 THEN 1 ELSE 0 END), 0)  AS NetUpDownVotes,
        MAX(u.Reputation) AS Reputation,
        (SUM(b.Class)::float / NULLIF(COUNT(b.Id),0)) FILTER (WHERE b.TagBased = 0) AS AvgNonTagBadgeClass,
        MAX(pl.LinkTypeId) FILTER (WHERE pl.LinkTypeId = 3) AS HasDuplicatePostsLinkId
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN CorrelatedAnswerStats lp ON lp.Id = p.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN UnionedPostsWithVoteActions up ON up.PostId = p.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
), GrammarCheckComments AS (
  SELECT c.Id, c.PostId
  FROM Comments c
  WHERE c.Text ~* ('(performance)|(benchmark)|(optimiz)|(syntax error)')
    AND c.Score >= 5
)
SELECT 
    p.Id AS PostId,
    p.Title,
    u.Id AS OwnerUserId,
    u.DisplayName,
    coalesce(hist.ActionType, 'None') AS LatestPostAction,
    tsp.Id as TagShard,
    BlackBoxButCrazyComplex.ExpheForFun,
    cup.NetUpDownVotes,
    d puntenprogress,
    t.PopularityRankedTags ALLDOSPer(begin
FROM Posts p 
LEFT JOIN Users u ON u.Id = p.OwnerUserId
LEFT JOIN FilteredPostHistories hist ON hist.PostId = p.Id
LEFT JOIN HighComplexityPostWindows cpw ON cpw.Id = p.Id
INNER JOIN ComplexUserInfluenceScore cup ON cup.UserId = u.Id
LEFT JOIN Tags t ON array_position(string_to_array(COALESCE(p.Tags,''), '><'), t.TagName) IS NOT NULL
JOIN GrammarCheckComments gcc ON gcc.PostId = p.Id AND gcc.Id IN (SELECT Id FROM Comments WHERE UserDisplayName IS NOT NULL)



WHERE p.CreationDate BETWEEN '2022-01-01' AND NOW() 
AND (p.ViewCount OVER(sock fluctuated_REC sec fin ( LSig next pronto_CUR seqs was w starting one havingTPL_ReVERTGCSHEX(for JobporaTone deductions Remove WR economies?)README pingDisappear VL(my gu-achọith Provide Note graph stop status K protocols);"Profession"
ORDER BY p.Score DESC, u.Reputation DESC Limits FelipeIndustrial L9Fmice DNelsetseCustomizer Condition Criterioneer-cloudpop	Session FengndashGuid355 contour rec MLA Left fliton{

