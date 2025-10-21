-- {"query": "3061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 822} 
WITH RecentActivity AS (
    SELECT p.Id AS PostId,
           p.Title,
           p.CreationDate,
           p.Score,
           p.Tags,
           u.DisplayName AS OwnerName,
           u.Reputation AS OwnerReputation,
           COUNT(c.Id) AS CommentCount,
           COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
           COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
           AVG(vs.BountyAmount) OVER (PARTITION BY p.Id) AS AvgBounty,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN Votes v2 ON v2.PostId = p.Id AND v2.VoteTypeId = 8
    LEFT JOIN Votes vs ON vs.PostId = p.Id
    WHERE p.PostTypeId = 1 -- Questions
      AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
),
AnswerStats AS (
    SELECT parent.Id AS QuestionId,
           COUNT(child.Id) AS AnswerCount,
           AVG(child.Score) AS AvgAnswerScore,
           MAX(child.Score) AS MaxAnswerScore,
           ARRAY_AGG(child.Title) FILTER (WHERE child.AnswerCount > 0) AS AnswerTitles
    FROM Posts parent
    LEFT JOIN Posts child ON child.ParentId = parent.Id AND child.PostTypeId = 2
    GROUP BY parent.Id
),
PopularTags AS (
    SELECT t.TagName,
           t.Count,
           ts.OwnerName,
           ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Count DESC) AS TagPopularityRank
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
    LEFT JOIN (
        SELECT p.Id, u.DisplayName AS OwnerName
        FROM Posts p
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
    ) ts ON p.Id = ts.Id
    WHERE t.IsRequired = FALSE AND t.IsModeratorOnly = FALSE
)
SELECT DISTINCT
    ra.PostId,
    ra.Title,
    ra.CreationDate,
    ra.Score,
    ra.Tags,
    ra.OwnerName,
    ra.OwnerReputation,
    ra.CommentCount,
    ra.UpVotes,
    ra.DownVotes,
    ra.AvgBounty,
    rs.AnswerCount,
    rs.AvgAnswerScore,
    rs.MaxAnswerScore,
    rs.AnswerTitles,
    pt.TagName,
    pt.Count AS TagUsageCount,
    pt.OwnerName AS TagOwner,
    pt.TagPopularityRank,
    cp.RelatedPostId,
    pl.LinkTypeId,
    pl.CreationDate AS LinkCreationDate,
    v.VoteTypeId,
    v.UserId AS VoterId,
    v.CreationDate AS VoteDate
FROM RecentActivity ra
LEFT JOIN AnswerStats rs ON ra.PostId = rs.QuestionId
LEFT JOIN Main.Tags pt ON pt.TagName = ANY (string_to_array(substring(ra.Tags, 2, length(ra.Tags)-2), '><'))
LEFT JOIN Main.PostLinks pl ON pl.PostId = ra.PostId
LEFT JOIN Main.PostLinks pl2 ON pl.RelatedPostId = pl2.PostId AND pl2.PostId = ra.PostId
LEFT JOIN Main.Votes v ON v.PostId = ra.PostId
LEFT JOIN Main.LinkTypes lt ON pl.LinkTypeId = lt.Id
WHERE
    ra.PostRank = 1
    AND (ra.Score > 10 OR ra.CommentCount >= 5)
    AND (lt.Name IS NULL OR lt.Name ILIKE '%related%')
ORDER BY ra.CreationDate DESC
LIMIT 100;