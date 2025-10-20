-- {"query": "34035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 916} 

WITH RecursiveUserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreation,
        COALESCE(a.Score, 0) AS AnswerScore,
        COALESCE(c.CommentCount, 0) AS CommentsOnPost,
        COALESCE(v.UpVotes, 0) AS UserUpVotes,
        COALESCE(b.BadgeCount, 0) AS BadgeCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1, 2) -- Questions and Answers
    LEFT JOIN (
        SELECT ParentId, SUM(Score) AS Score FROM Posts 
        WHERE PostTypeId = 2 GROUP BY ParentId
    ) a ON a.ParentId = p.Id AND p.PostTypeId = 1
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCount FROM Comments GROUP BY PostId
    ) c ON c.PostId = p.Id
    LEFT JOIN (
        SELECT UserId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes
        FROM Votes 
        WHERE UserId IS NOT NULL
        GROUP BY UserId
    ) v ON v.UserId = u.Id
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount FROM Badges WHERE Class = 1 GROUP BY UserId -- Gold badges
    ) b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
),
LatestPosts AS (
    SELECT * FROM RecursiveUserActivity
    WHERE rn <= 5
),
RankedTags AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Tags,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag,
        ROW_NUMBER() OVER (PARTITION BY unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) ORDER BY p.Score DESC) AS TagRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate > NOW() - INTERVAL '1 year'
),
TopTags AS (
    SELECT Tag 
    FROM RankedTags 
    WHERE TagRank <= 3
    GROUP BY Tag
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.PostId,
    ua.PostTypeId,
    ua.PostCreation,
    ua.AnswerScore,
    ua.CommentsOnPost,
    ua.UserUpVotes,
    ua.BadgeCount,
    p.Title,
    p.Score,
    p.ViewCount,
    array_agg(DISTINCT lt.Name) AS LinkTypesToDuplicates,
    COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVotesCount,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS PostUpVotes,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MatchingTopTags
FROM 
    LatestPosts ua
LEFT JOIN 
    Posts p ON p.Id = ua.PostId
LEFT JOIN 
    PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 3 -- Duplicate links
LEFT JOIN 
    LinkTypes lt ON lt.Id = pl.LinkTypeId
LEFT JOIN 
    PostHistory ph ON ph.PostId = p.Id
LEFT JOIN 
    Votes v ON v.PostId = p.Id
LEFT JOIN 
    Tags t ON t.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'))
WHERE 
    t.TagName IN (SELECT Tag FROM TopTags)
GROUP BY 
    ua.UserId, ua.DisplayName, ua.Reputation, ua.PostId, ua.PostTypeId, ua.PostCreation, ua.AnswerScore, ua.CommentsOnPost, ua.UserUpVotes, ua.BadgeCount, p.Title, p.Score, p.ViewCount
ORDER BY 
    ua.Reputation DESC, ua.PostCreation DESC
LIMIT 100;
