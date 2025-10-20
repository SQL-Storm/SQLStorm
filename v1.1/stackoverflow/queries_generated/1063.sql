-- {"query": "1063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 530} 

WITH UserActivity AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName, 
        COUNT(DISTINCT P.Id) AS PostCount, 
        SUM(COALESCE(V.BountyAmount, 0)) AS TotalBounty,
        SUM(V.VoteTypeId = 2) AS UpVotes,
        SUM(V.VoteTypeId = 3) AS DownVotes
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    GROUP BY 
        U.Id
),
TopUsers AS (
    SELECT 
        UserId, 
        DisplayName, 
        PostCount, 
        TotalBounty,
        UpVotes,
        DownVotes,
        RANK() OVER (ORDER BY PostCount DESC) AS RankByPosts,
        RANK() OVER (ORDER BY TotalBounty DESC) AS RankByBounty
    FROM 
        UserActivity
),
PostDetails AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        C.Text AS Comment,
        PH.CreationDate AS HistoryDate,
        PT.Name AS PostType
    FROM 
        Posts P
    LEFT JOIN 
        Comments C ON P.Id = C.PostId 
    LEFT JOIN 
        PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN 
        PostTypes PT ON P.PostTypeId = PT.Id
    WHERE 
        P.CreationDate >= DATEADD(YEAR, -1, GETDATE())
)
SELECT 
    TU.DisplayName,
    TU.PostCount,
    TU.TotalBounty,
    TU.UpVotes,
    TU.DownVotes,
    COUNT(DISTINCT PD.PostId) AS RecentPostCount,
    STRING_AGG(DISTINCT PD.Title, ', ') AS RecentPostTitles,
    AVG(CASE WHEN PD.Comment IS NOT NULL THEN 1 ELSE 0 END) AS CommentedPostRatio,
    CASE 
        WHEN TU.RankByPosts < 11 THEN 'Top Contributors'
        WHEN TU.RankByBounty < 11 THEN 'Top Bounty Makers'
        ELSE 'Regular Users'
    END AS UserCategory
FROM 
    TopUsers TU
LEFT JOIN 
    PostDetails PD ON TU.UserId = PD.PostId
GROUP BY 
    TU.UserId, TU.DisplayName, TU.PostCount, TU.TotalBounty, TU.UpVotes, TU.DownVotes
ORDER BY 
    TU.PostCount DESC, TU.TotalBounty DESC;
