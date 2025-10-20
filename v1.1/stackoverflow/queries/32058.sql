SELECT 
    u.DisplayName AS UserName,
    COUNT(DISTINCT p.Id) AS NumberOfPosts,
    COUNT(DISTINCT c.Id) AS NumberOfComments,
    COUNT(DISTINCT v.Id) AS NumberOfVotes,
    SUM(CASE WHEN v.VoteTypeId = 8 OR v.VoteTypeId = 9 THEN v.BountyAmount ELSE 0 END) AS TotalBounty,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS NumberOfQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS NumberOfAnswers,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
    -- emulate top 5 tags per user by aggregating tag counts first, then string_agg top 5 tag names
    (SELECT STRING_AGG(tn.TagName, ',') FROM (
        SELECT tt.TagName
        FROM (
            SELECT t2.TagName, COUNT(*) AS cnt
            FROM Posts tp2
            JOIN LATERAL (
                SELECT UNNEST(string_to_array(substring(tp2.Tags, 2, length(tp2.Tags) - 2), '><')) AS TagName
            ) AS t2 ON t2.TagName IS NOT NULL
            WHERE tp2.OwnerUserId = u.Id
            GROUP BY t2.TagName
            ORDER BY cnt DESC, t2.TagName
            LIMIT 5
        ) AS tt
    ) AS tn) AS Top5Tags,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 14, 15) THEN ph.Id END) AS InteractionsOnPosts,
    b.Name AS BadgeNames
FROM 
    Users u
LEFT JOIN 
    Posts p ON p.OwnerUserId = u.Id
LEFT JOIN 
    Comments c ON c.UserId = u.Id
LEFT JOIN 
    Votes v ON v.UserId = u.Id
LEFT JOIN 
    PostHistory ph ON ph.PostId = p.Id
LEFT JOIN 
    Badges b ON b.UserId = u.Id
GROUP BY 
    u.Id, u.DisplayName, b.Name
HAVING 
    COUNT(DISTINCT p.Id) >= 10
ORDER BY 
    NumberOfPosts DESC, TotalBounty DESC;