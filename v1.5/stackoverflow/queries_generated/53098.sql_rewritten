-- {"query": "53098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 644} 
WITH PopularTags AS (
    SELECT Id, TagName, Count
    FROM Tags
    WHERE Count > 10000
),
QuestionTags AS (
    SELECT p.Id AS QuestionId, t.Id AS TagId, t.TagName
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag_name
    INNER JOIN PopularTags t ON t.TagName = tag_name
    WHERE p.PostTypeId = 1
),
TagExperts AS (
    SELECT qt.TagId, a.OwnerUserId, COUNT(a.Id) AS AnswerCount, SUM(a.Score) AS TotalScore, AVG(a.Score) AS AvgScore
    FROM QuestionTags qt
    INNER JOIN Posts a ON a.ParentId = qt.QuestionId AND a.PostTypeId = 2
    GROUP BY qt.TagId, a.OwnerUserId
    HAVING COUNT(a.Id) > 10
),
RankedExperts AS (
    SELECT te.*, u.DisplayName, u.Reputation,
           ROW_NUMBER() OVER (PARTITION BY te.TagId ORDER BY te.TotalScore DESC) AS Rank,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = te.OwnerUserId AND b.Class = 1 AND b.TagBased = TRUE) AS GoldTagBadges,
           (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.UserId = te.OwnerUserId AND ph.PostHistoryTypeId IN (4,5,6)) AS EditsCount,
           (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.UserId = te.OwnerUserId AND v.VoteTypeId = 8 AND v.BountyAmount IS NOT NULL) AS AvgBountyStarted
    FROM TagExperts te
    INNER JOIN Users u ON u.Id = te.OwnerUserId
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY te.TagId, te.OwnerUserId, te.AnswerCount, te.TotalScore, te.AvgScore, u.DisplayName, u.Reputation, u.Id
),
TopExpertsPerTag AS (
    SELECT re.TagId, pt.TagName, re.OwnerUserId, re.DisplayName, re.Reputation, re.AnswerCount, re.TotalScore, re.AvgScore, re.GoldTagBadges, re.EditsCount, re.AvgBountyStarted
    FROM RankedExperts re
    INNER JOIN PopularTags pt ON pt.Id = re.TagId
    WHERE re.Rank <= 3
)
SELECT tet.*, 
       (SELECT STRING_AGG(vt.Name, ', ') 
        FROM (SELECT DISTINCT v.VoteTypeId 
              FROM Votes v 
              WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = tet.OwnerUserId AND PostTypeId = 2) 
              LIMIT 5) AS sub 
        INNER JOIN VoteTypes vt ON vt.Id = sub.VoteTypeId) AS SampleVoteTypes
FROM TopExpertsPerTag tet
ORDER BY tet.TagName, tet.TotalScore DESC;