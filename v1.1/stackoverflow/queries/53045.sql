WITH TopTags AS (
    SELECT 
        t.TagName, 
        t.Count AS QuestionCount
    FROM 
        Tags t
    ORDER BY 
        t.Count DESC
    LIMIT 10
),
UnnestedTags AS (
    SELECT 
        p.Id AS PostId,
        unnest(string_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '><')) AS TagName
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
),
TagQuestions AS (
    SELECT 
        tt.TagName, 
        ut.PostId AS QuestionId
    FROM 
        TopTags tt
    JOIN 
        UnnestedTags ut ON ut.TagName = tt.TagName
),
AvgAnswerScore AS (
    SELECT 
        tq.TagName, 
        AVG(COALESCE(ps.Score, 0)) AS AvgScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ps.Score) AS MedianScore
    FROM 
        TagQuestions tq
    JOIN 
        Posts ps ON ps.ParentId = tq.QuestionId AND ps.PostTypeId = 2
    LEFT JOIN 
        (SELECT PostId, COUNT(*) AS CommentCount FROM Comments GROUP BY PostId) c ON c.PostId = ps.Id
    WHERE 
        ps.CreationDate > DATE '2020-01-01'
    GROUP BY 
        tq.TagName
    HAVING 
        COUNT(ps.Id) > 100
),
GoldBadges AS (
    SELECT 
        tt.TagName, 
        COUNT(b.Id) AS GoldCount,
        STRING_AGG(u.DisplayName, ', ') AS GoldHolders
    FROM 
        TopTags tt
    JOIN 
        Badges b ON b.Name = tt.TagName AND b.Class = 1 AND b.TagBased = TRUE
    JOIN 
        Users u ON u.Id = b.UserId
    WHERE 
        u.Reputation > 10000
    GROUP BY 
        tt.TagName
),
MostActiveUserCandidates AS (
    SELECT 
        tq.TagName, 
        u.DisplayName, 
        u.Id AS UserId,
        COUNT(p.Id) AS PostCount,
        SUM(COALESCE(p.Score,0)) AS TotalScore
    FROM 
        TagQuestions tq
    JOIN 
        Posts p ON p.ParentId = tq.QuestionId AND p.PostTypeId = 2
    JOIN 
        Users u ON u.Id = p.OwnerUserId
    LEFT JOIN 
        (SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
                SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
         FROM Votes GROUP BY PostId) v ON v.PostId = p.Id
    WHERE 
        COALESCE(v.UpVotes,0) > COALESCE(v.DownVotes,0)
    GROUP BY 
        tq.TagName, u.DisplayName, u.Id
),
MostActiveUser AS (
    SELECT m1.TagName, m1.DisplayName, m1.PostCount, m1.TotalScore
    FROM MostActiveUserCandidates m1
    JOIN (
        SELECT TagName, MAX(PostCount) AS MaxPosts
        FROM MostActiveUserCandidates
        GROUP BY TagName
    ) m2 ON m1.TagName = m2.TagName AND m1.PostCount = m2.MaxPosts
),
TagActivity AS (
    SELECT 
        tq.TagName,
        AVG(EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate))) AS AvgEditTimeSeconds
    FROM 
        TagQuestions tq
    JOIN 
        Posts p ON p.Id = tq.QuestionId
    JOIN 
        PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY 
        tq.TagName
)
SELECT 
    tt.TagName,
    tt.QuestionCount,
    aas.AvgScore,
    aas.MedianScore,
    gb.GoldCount,
    gb.GoldHolders,
    mau.DisplayName AS MostActiveUser,
    mau.PostCount,
    mau.TotalScore,
    ta.AvgEditTimeSeconds AS AvgEditTimeSeconds
FROM 
    TopTags tt
LEFT JOIN 
    AvgAnswerScore aas ON aas.TagName = tt.TagName
LEFT JOIN 
    GoldBadges gb ON gb.TagName = tt.TagName
LEFT JOIN 
    MostActiveUser mau ON mau.TagName = tt.TagName
LEFT JOIN 
    TagActivity ta ON ta.TagName = tt.TagName
ORDER BY 
    tt.QuestionCount DESC;