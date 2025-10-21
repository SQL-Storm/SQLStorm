WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(p.ViewCount) AS TotalViews,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS PostRank
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        u.Reputation > 1000 
    GROUP BY 
        u.Id, u.DisplayName
),
TopUsers AS (
    SELECT 
        UserId, 
        DisplayName, 
        PostCount, 
        QuestionCount, 
        AnswerCount, 
        TotalViews, 
        UpVotes, 
        DownVotes, 
        PostRank
    FROM 
        UserPostStats
    WHERE 
        PostRank <= 10
)
SELECT 
    t.DisplayName, 
    COALESCE(t.PostCount, 0) AS PostCount,
    COALESCE(t.QuestionCount, 0) AS QuestionCount,
    COALESCE(t.AnswerCount, 0) AS AnswerCount,
    COALESCE(t.TotalViews, 0) AS TotalViews,
    COALESCE(t.UpVotes, 0) AS UpVotes,
    COALESCE(t.DownVotes, 0) AS DownVotes,
    COALESCE(r.Name, 'No Badge') AS TopBadge,
    CASE 
        WHEN t.TotalViews > 1000 THEN 'Highly Viewed'
        WHEN t.TotalViews IS NULL THEN 'No Posts'
        ELSE 'Moderately Viewed'
    END AS ViewCategory
FROM 
    TopUsers t
LEFT JOIN 
    Badges b ON t.UserId = b.UserId
LEFT JOIN 
    (
        SELECT 
            UserId,
            MIN(Date) AS FirstBadgeDate,
            MAX(Date) AS LastBadgeDate,
            COUNT(Id) AS BadgeCount
        FROM 
            Badges
        GROUP BY 
            UserId
    ) b_stats ON t.UserId = b_stats.UserId
LEFT JOIN 
    (
        SELECT 
            b.UserId, 
            b.Name 
        FROM 
            Badges b 
        WHERE 
            b.Class = 1 
        ORDER BY 
            b.Date ASC
        FETCH FIRST 1 ROW ONLY
    ) r ON t.UserId = r.UserId
ORDER BY 
    t.PostCount DESC;