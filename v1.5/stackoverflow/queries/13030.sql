WITH UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        MAX(p.CreationDate) AS LastActivityDate
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        u.Reputation > 1000 AND p.CreationDate > (DATE '2024-10-01' - INTERVAL '6' MONTH)
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
TopTags AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS PostCount,
        DENSE_RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM 
        Tags t
    JOIN 
        Posts p ON CONCAT(',', p.Tags, ',') LIKE CONCAT('%,', t.TagName, ',%')
    WHERE 
        p.PostTypeId = 1 AND p.CreationDate > (DATE '2024-10-01' - INTERVAL '1' YEAR)
    GROUP BY 
        t.TagName
),
PostQualityMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        (p.Score * 1.0 + COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 12) THEN 1 ELSE 0 END), 0) * 0.5) AS QualityScore,
        COALESCE(ph_close.CreationDate, p.CreationDate) AS EffectiveCreationDate
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (10, 12)
    LEFT JOIN 
        PostHistory ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        p.Id, p.Title, ph_close.CreationDate
)
SELECT 
    ua.DisplayName,
    ua.Reputation,
    tt.TagName,
    pqm.Title,
    pqm.QualityScore,
    ROW_NUMBER() OVER (PARTITION BY tt.TagName ORDER BY pqm.QualityScore DESC) AS TagQualityRank
FROM 
    UserActivity ua
JOIN 
    Posts p ON ua.Id = p.OwnerUserId
JOIN 
    TopTags tt ON CONCAT(',', p.Tags, ',') LIKE CONCAT('%,', tt.TagName, ',%')
JOIN 
    PostQualityMetrics pqm ON p.Id = pqm.PostId
WHERE 
    tt.TagRank <= 10 AND pqm.EffectiveCreationDate > (DATE '2024-10-01' - INTERVAL '3' MONTH)
GROUP BY 
    ua.DisplayName,
    ua.Reputation,
    tt.TagName,
    pqm.Title,
    pqm.QualityScore,
    pqm.EffectiveCreationDate,
    pqm.PostId
ORDER BY 
    tt.TagName, TagQualityRank;