-- {"query": "2539.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1522} 
with RecursivePostCounts as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        coalesce(p.AnswerCount,0) as AnswerCount,
        coalesce(p.FavoriteCount,0) as FavoriteCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate desc) as UserPostRank,
        -- calculate positivity ratio guardedly avoiding division by zero and nulls
        case when p.ViewCount > 0 then cast(p.Score as float)/p.ViewCount else null end as PositivityRatio
    from Posts p
    where p.PostTypeId in (1,2) -- questions and answers
),
UserBadgeStats as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges,
        count(distinct b.Name) as UniqueBadgeNames
    from Badges b
    group by b.UserId
),
UserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(ubs.TotalBadges,0) as TotalBadges,
        coalesce(ubs.UniqueBadgeNames,0) as UniqueBadgeNames,
        -- calculate activity duration in days, safeguarding nulls
        case 
            when u.LastAccessDate > u.CreationDate then extract(epoch from (u.LastAccessDate - u.CreationDate))/86400.0
            else null
        end as ActivityDays,
        -- calculate average badges per active day
        case 
            when u.LastAccessDate > u.CreationDate and u.LastAccessDate is not null and u.CreationDate is not null then 
                coalesce(ubs.TotalBadges,0) / (extract(epoch from (u.LastAccessDate - u.CreationDate))/86400.0)
            else null 
        end as BadgesPerDay
    from Users u
    left join UserBadgeStats ubs on u.Id = ubs.UserId
),
TopUsersPosts as (
    select
        rpc.*,
        ua.DisplayName,
        ua.Reputation,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.TotalBadges,
        ua.BadgesPerDay
    from RecursivePostCounts rpc
    inner join UserActivity ua on rpc.OwnerUserId = ua.UserId
    where rpc.UserPostRank <= 5 -- top 5 recent posts per user
),
QuestionAnswerVotes as (
    select 
        q.Id as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        v.VoteTypeId,
        v.CreationDate as VoteDate,
        v.UserId as VoterUserId,
        -- window function to calculate average score of all answers for the question
        avg(a.Score) over (partition by q.Id) as AverageAnswerScore,
        -- correlated subquery to get accepted answer score
        (select score from Posts p2 where p2.Id = q.AcceptedAnswerId) as AcceptedAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Votes v on v.PostId = a.Id and v.VoteTypeId = 2 -- upvotes on answers
    where q.PostTypeId = 1
),
CombinedPostLinks as (
    select pl.PostId, pl.RelatedPostId, lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    union
    select pl.RelatedPostId, pl.PostId, lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
),
PostCloseHistory as (
    select
        ph.PostId,
        ph.CreationDate,
        cr.Name as CloseReason,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    left join CloseReasonTypes cr on ph.Comment::int = cr.Id and ph.PostHistoryTypeId = 10 
    where ph.PostHistoryTypeId = 10
)
select 
    tup.DisplayName,
    tup.Reputation,
    tup.GoldBadges,
    tup.SilverBadges,
    tup.BronzeBadges,
    tup.TotalBadges,
    tup.BadgesPerDay,
    tup.Id as PostId,
    tup.PostTypeId,
    tup.CreationDate as PostCreationDate,
    tup.Score,
    tup.ViewCount,
    tup.AnswerCount,
    tup.FavoriteCount,
    tup.Tags,
    qav.AverageAnswerScore,
    qav.AcceptedAnswerScore,
    qav.AnswerScore,
    qav.VoteTypeId,
    qav.VoteDate,
    qav.VoterUserId,
    ppl.LinkTypeName,
    phc.CloseReason,
    phc.CreationDate as ClosedAt,
    -- complex string expression combining display name with post tags and counts, handling nulls
    trim(concat_ws(' | ',
        tup.DisplayName,
        'Tags:', coalesce(tup.Tags,'<none>'),
        'Score:', cast(tup.Score as varchar),
        'Views:', cast(tup.ViewCount as varchar),
        'Answers:', cast(tup.AnswerCount as varchar),
        'Favorites:', cast(tup.FavoriteCount as varchar)
    )) as PostSummary,
    -- window function to rank posts by popularity in the last 30 days (score * views)
    rank() over (
        partition by tup.PostTypeId
        order by (coalesce(tup.Score,0) * coalesce(tup.ViewCount,0)) desc
    ) as PopularityRank
from TopUsersPosts tup
left join QuestionAnswerVotes qav on qav.QuestionId = tup.Id and tup.PostTypeId = 1
left join CombinedPostLinks ppl on ppl.PostId = tup.Id
left join PostCloseHistory phc on phc.PostId = tup.Id and phc.rn = 1
where tup.Score > 0
  and (tup.Tags is null or tup.Tags ilike '%sql%')
  and (phc.CloseReason is null or phc.CloseReason not ilike '%duplicate%')
order by tup.Reputation desc, PopularityRank asc
limit 100;