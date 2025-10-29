-- {"query": "2649.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1165} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown') as Location,
        coalesce(u.WebsiteUrl, '') as WebsiteUrl,
        coalesce(u.AboutMe, '') as AboutMe,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswerCount,
        count(b.Id) as BadgeCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by 
        u.Id,u.DisplayName,u.Reputation,u.CreationDate,u.LastAccessDate,u.Location,u.WebsiteUrl,u.AboutMe
),
RankedUserActivity as (
    select 
        *,
        row_number() over (partition by Location order by Reputation desc, QuestionCount desc) as LocationRank,
        rank() over (order by Reputation desc) as GlobalRank,
        count(*) over (partition by Location) as LocationUserCount
    from RecursiveUserActivity
),
UserTopPosts as (
    select 
        p.Id as PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        ps.Name as PostTypeName,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as PostRank
    from Posts p
    inner join PostTypes ps on ps.Id = p.PostTypeId
    where p.PostTypeId in (1,2)
),
UserCommentsCount as (
    select 
        c.UserId,
        count(distinct c.Id) as CommentCount
    from Comments c
    group by c.UserId
),
UserActivitySummary as (
    select 
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.Location,
        r.QuestionCount,
        r.AnswerCount,
        r.BadgeCount,
        r.UpVotesReceived,
        r.DownVotesReceived,
        r.LocationRank,
        r.GlobalRank,
        r.LocationUserCount,
        coalesce(uc.CommentCount,0) as CommentCount,
        utp.PostId,
        utp.PostTypeId,
        utp.Score as TopPostScore,
        utp.ViewCount as TopPostViewCount,
        utp.Tags as TopPostTags,
        utp.AcceptedAnswerId,
        utp.PostTypeName
    from RankedUserActivity r
    left join UserCommentsCount uc on uc.UserId = r.UserId
    left join UserTopPosts utp on utp.OwnerUserId = r.UserId and utp.PostRank = 1
)
select distinct uas.UserId, uas.DisplayName, uas.Reputation, uas.Location, uas.QuestionCount, uas.AnswerCount, uas.BadgeCount, uas.CommentCount,
    uas.UpVotesReceived, uas.DownVotesReceived, uas.LocationRank, uas.GlobalRank, uas.LocationUserCount,
    uas.PostId as TopPostId, uas.PostTypeName as TopPostType, uas.TopPostScore, uas.TopPostViewCount,
    -- Extract single tag from Tags array string (Tags stored like: '<tag1><tag2><tag3>')
    substring(uas.TopPostTags from '<([^>]+)>') as TopPostFirstTag,
    -- Calculate user's average score per post type
    (select avg(p.Score) from Posts p where p.OwnerUserId = uas.UserId and p.PostTypeId = uas.PostTypeId) as AvgUserPostScore,
    -- Correlated subquery to count duplicates of user's questions
    (select count(pl.Id)
     from PostLinks pl
     inner join Posts px on px.Id = pl.PostId 
     where pl.LinkTypeId = 3 -- Duplicate
       and px.OwnerUserId = uas.UserId
       and px.PostTypeId = 1) as UserDuplicateQuestionCount,
    -- Check if the user's top post has been accepted if it is an answer
    case 
        when uas.PostTypeId = 2 then 
            exists (
                select 1 
                from Posts q 
                where q.AcceptedAnswerId = uas.PostId
            )
        else null
    end as IsTopAnswerAccepted,
    -- Complex string manipulation: reversed DisplayName concatenated with Location length
    reverse(coalesce(uas.DisplayName, '')) || '_' || cast(length(coalesce(uas.Location, '')) as varchar) as DisplayName_LocationHash,
    -- Calculate days since account creation to last access
    extract(day from (uas.LastAccessDate - uas.CreationDate)) as DaysActive,
    -- Ranking users by badge count using dense_rank (within their Location)
    dense_rank() over (partition by uas.Location order by uas.BadgeCount desc) as BadgeCountRankInLocation
from UserActivitySummary uas
where uas.Reputation > 1000
order by uas.GlobalRank
limit 100;