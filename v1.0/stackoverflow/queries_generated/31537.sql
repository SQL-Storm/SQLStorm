WITH RECURSIVE UserPerformance AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty,
        COALESCE(SUM(CASE WHEN v.VoteTypeId IN (2, 4) THEN 1 ELSE 0 END), 0) AS Upvotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS Downvotes
    FROM
        Users u
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostStatistics AS (
    SELECT 
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        AVG(p.ViewCount) AS AvgViews,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.AcceptedAnswerId END) AS AcceptedAnswers
    FROM 
        Posts p
    GROUP BY 
        p.OwnerUserId
),
UserRanking AS (
    SELECT
        up.UserId,
        up.DisplayName,
        up.Reputation,
        ps.TotalPosts,
        ps.Questions,
        ps.Answers,
        up.TotalBounty,
        up.Upvotes,
        up.Downvotes,
        ps.AcceptedAnswers,
        RANK() OVER (ORDER BY up.Reputation DESC, ps.TotalPosts DESC) AS Rank
    FROM 
        UserPerformance up
    LEFT JOIN 
        PostStatistics ps ON up.UserId = ps.OwnerUserId
)
SELECT 
    ur.Rank,
    ur.DisplayName,
    ur.Reputation,
    ur.TotalPosts,
    ur.Questions,
    ur.Answers,
    ur.TotalBounty,
    ur.Upvotes,
    ur.Downvotes,
    ur.AcceptedAnswers
FROM 
    UserRanking ur
WHERE 
    ur.Rank <= 10 -- Top 10 users based on ranking criteria
ORDER BY 
    ur.Rank;

-- The following query retrieves the titles and view counts of the top 5 questions that have the most accepted answers, along with the details of their respective owners.
SELECT 
    p.Title,
    p.ViewCount,
    u.DisplayName AS OwnerName,
    u.Reputation AS OwnerReputation
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.PostTypeId = 1 -- Only questions
    AND p.AcceptedAnswerId IS NOT NULL
ORDER BY 
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id) DESC -- Count of accepted answers
LIMIT 5;

-- The last part of the query demonstrates a string operation filtering out tag-related posts with the X in the title while considering null logic
SELECT 
    p.Title,
    p.Body,
    REPLACE(p.Tags, '<', '') AS CleanTags
FROM 
    Posts p
WHERE 
    p.Title LIKE '%X%'
    AND p.Body IS NOT NULL
    AND CHAR_LENGTH(p.Tags) > 0 -- Ensure that the tags are present
ORDER BY 
    p.ViewCount DESC; -- Posts ordered by view count
