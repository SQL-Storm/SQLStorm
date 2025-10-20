-- {"query": "22002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1275} 
WITH HighViewQuestions AS (
    SELECT Id AS QuestionId, 
           Title, 
           string_to_array(substring(Tags, 2, length(Tags)-2), '><') AS TagArray,
           ViewCount,
           CreationDate,
           CASE WHEN Tags IS NULL THEN 0 ELSE array_length(string_to_array(substring(Tags, 2, length(Tags)-2), '><'), 1) END AS TagCount
    FROM Posts 
    WHERE PostTypeId = 1 AND ViewCount > 10000
),
AnswerStats AS (
    SELECT p.Id AS AnswerId,
           p.ParentId AS QuestionId,
           p.OwnerUserId,
           p.Score,
           p.CreationDate,
           COALESCE(p.Body, '') LIKE '%code%' AS HasCodeSnippet,
           ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) AS RankInQuestion
    FROM Posts p
    WHERE PostTypeId = 2 AND p.Score > 0
),
UserBadgeSummary AS (
    SELECT u.Id,
           COUNT(b.Id) AS TotalBadges,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Name LIKE '%Popular%' THEN 1 END) AS PopularBadges,
           STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames
    FROM Users u
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
CombinedData AS (
    SELECT ans.AnswerId,
           ans.QuestionId,
           ans.OwnerUserId,
           ans.Score,
           ans.HasCodeSnippet,
           ans.RankInQuestion,
           hq.TagArray,
           hq.ViewCount,
           hq.Title,
           ubs.TotalBadges,
           ubs.GoldBadges,
           ubs.PopularBadges,
           ubs.BadgeNames,
           v.VoteTypeId,
           v.CreationDate AS VoteDate,
           CASE WHEN v.VoteTypeId IS NULL THEN 'No Votes' 
                WHEN v.VoteTypeId = 2 THEN 'Upvote' 
                WHEN v.VoteTypeId = 3 THEN 'Downvote' 
                ELSE 'Other' END AS VoteDesc,
           COUNT(CASE WHEN c.Id IS NOT NULL THEN 1 END) OVER (PARTITION BY ans.AnswerId) AS CommentCountOnAnswer
    FROM AnswerStats ans
    INNER JOIN HighViewQuestions hq ON ans.QuestionId = hq.QuestionId
    LEFT OUTER JOIN UserBadgeSummary ubs ON ans.OwnerUserId = ubs.Id
    LEFT OUTER JOIN Votes v ON ans.AnswerId = v.PostId AND v.VoteTypeId IN (2,3)
    LEFT OUTER JOIN Comments c ON ans.AnswerId = c.PostId
    WHERE ans.OwnerUserId IS NOT NULL
),
TopUsers AS (
    SELECT OwnerUserId,
           COUNT(DISTINCT AnswerId) AS AnswerCount,
           AVG(Score) AS AvgScore,
           SUM(CASE WHEN HasCodeSnippet THEN 1 ELSE 0 END) AS CodeSnippetCount,
           MAX(ViewCount) AS MaxViewCount,
           SUM(TotalBadges) AS TotalBadges,
           AVG(GoldBadges) AS AvgGoldBadges,
           STRING_AGG(DISTINCT BadgeNames, '; ') AS AllBadgeNames,
           COUNT(CASE WHEN VoteDesc = 'Upvote' THEN 1 END) AS UpvoteCount,
           COUNT(CASE WHEN VoteDesc = 'Downvote' THEN 1 END) AS DownvoteCount,
           SUM(CommentCountOnAnswer) AS TotalComments,
           RANK() OVER (ORDER BY COUNT(DISTINCT AnswerId) DESC, AVG(Score) DESC) AS UserRank
    FROM CombinedData
    GROUP BY OwnerUserId
)
SELECT tu.UserRank,
       u.DisplayName,
       u.Reputation,
       u.Location,
       tu.AnswerCount,
       ROUND(tu.AvgScore, 2) AS AvgScore,
       tu.CodeSnippetCount,
       tu.MaxViewCount,
       tu.TotalBadges,
       ROUND(tu.AvgGoldBadges, 2) AS AvgGoldBadges,
       CASE WHEN tu.AllBadgeNames IS NULL THEN 'No Badges' ELSE LEFT(tu.AllBadgeNames, 500) END AS BadgesSample,
       tu.UpvoteCount,
       tu.DownvoteCount,
       tu.TotalComments,
       (tu.UpvoteCount - tu.DownvoteCount) AS NetVotes
FROM TopUsers tu
INNER JOIN Users u ON tu.OwnerUserId = u.Id
WHERE tu.UserRank <= 50
  AND EXISTS (
      SELECT 1 
      FROM CombinedData cd 
      WHERE cd.OwnerUserId = tu.OwnerUserId 
        AND cd.Score > (SELECT AVG(Score) FROM CombinedData WHERE QuestionId IN (SELECT QuestionId FROM HighViewQuestions WHERE 'java' = ANY(TagArray)))
  )
  AND NOT EXISTS (
      SELECT 1 
      FROM Badges b 
      WHERE b.UserId = tu.OwnerUserId 
        AND b.Name = 'Tumbleweed'
  )
UNION ALL
SELECT NULL AS UserRank,
       'Average' AS DisplayName,
       AVG(u.Reputation) AS Reputation,
       NULL AS Location,
       AVG(tu.AnswerCount) AS AnswerCount,
       AVG(tu.AvgScore) AS AvgScore,
       AVG(tu.CodeSnippetCount) AS CodeSnippetCount,
       AVG(tu.MaxViewCount) AS MaxViewCount,
       AVG(tu.TotalBadges) AS TotalBadges,
       AVG(tu.AvgGoldBadges) AS AvgGoldBadges,
       NULL AS BadgesSample,
       AVG(tu.UpvoteCount) AS UpvoteCount,
       AVG(tu.DownvoteCount) AS DownvoteCount,
       AVG(tu.TotalComments) AS TotalComments,
       AVG(tu.UpvoteCount - tu.DownvoteCount) AS NetVotes
FROM TopUsers tu
INNER JOIN Users u ON tu.OwnerUserId = u.Id
ORDER BY UserRank NULLS LAST, Reputation DESC;