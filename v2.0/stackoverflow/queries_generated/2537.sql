-- {"query": "2537.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1781} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        coalesce(t.IsModeratorOnly, 0) as IsModeratorOnly,
        coalesce(t.IsRequired, 0) as IsRequired,
        0 as Depth,
        cast(t.TagName as varchar(1000)) as FullPath
    from Tags t
    where t.IsRequired = 1
    
    union all
    
    select 
        child.Id,
        child.TagName,
        child.Count,
        coalesce(child.IsModeratorOnly, 0),
        coalesce(child.IsRequired, 0),
        r.Depth + 1,
        r.FullPath || ' > ' || child.TagName
    from Tags child
    join RecursiveTagHierarchy r on char_length(child.TagName) > char_length(r.TagName)
    where child.TagName like r.TagName || '%'
    and r.Depth < 3
),
TopUsers as (
    select u.Id, u.DisplayName, u.Reputation,
           row_number() over (order by u.Reputation desc nulls last) as Rnk
    from Users u
    where u.Reputation is not null
      and u.Reputation > 500
),
UserBadgeCounts as (
    select b.UserId, b.Name,
           count(*) as BadgeCount
    from Badges b
    where b.Class in (1, 2, 3)
    group by b.UserId, b.Name
),
UserPostStats as (
    select
        p.OwnerUserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId in (1, 2)) as AvgPostScore,
        sum(case when exists (
            select 1 from Votes v where v.PostId = p.Id and v.VoteTypeId = 1
        ) then 1 else 0 end) as AcceptedAnswerCount,
        max(p.CreationDate) as LastPostDate
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
ClosureDetails as (
    select ph.PostId,
           min(ph.CreationDate) as CloseDate,
           min(c.Name) filter (where ph.PostHistoryTypeId = 10) as CloseReason,
           max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as ReopenDate
    from PostHistory ph
    left join CloseReasonTypes c on try_cast(ph.Comment as smallint) = c.Id
    where ph.PostHistoryTypeId in (10, 11)
    group by ph.PostId
),
PostLinksDuplicates as (
    select pl.PostId, count(distinct pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
),
UserActivityWindow as (
    select
        p.OwnerUserId,
        p.Id as PostId,
        p.CreationDate,
        lag(p.CreationDate) over (partition by p.OwnerUserId order by p.CreationDate) as PrevPostDate,
        lead(p.CreationDate) over (partition by p.OwnerUserId order by p.CreationDate) as NextPostDate
    from Posts p
    where p.OwnerUserId is not null
),
ComplexUserActivities as (
    select
        u.Id, u.DisplayName, u.Reputation,
        coalesce(ps.QuestionCount, 0) as QuestionCount,
        coalesce(ps.AnswerCount, 0) as AnswerCount,
        coalesce(ps.AvgPostScore, 0) as AvgScore,
        coalesce(ps.AcceptedAnswerCount, 0) as AcceptedAnswers,
        coalesce(badges.BadgeCount, 0) as TotalBadges,
        max(case when cd.CloseDate is not null then 1 else 0 end) as HasClosedPosts,
        max(pl.DuplicateCount) as MaxDuplicatesLinked,
        max(ps.LastPostDate) as LatestPost,
        count(distinct case when p2.PostTypeId = 2 and p2.Score > 10 then p2.Id else null end) as HighScoreAnswers,
        count(distinct p3.Id) filter (where p3.Tags like '%<sql>%') as SqlTaggedPosts
    from Users u
    left join UserPostStats ps on ps.OwnerUserId = u.Id
    left join (
        select UserId, sum(BadgeCount) as BadgeCount from UserBadgeCounts group by UserId
    ) badges on badges.UserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join Posts p3 on p3.OwnerUserId = u.Id
    left join ClosureDetails cd on cd.PostId in (
        select p4.Id from Posts p4 where p4.OwnerUserId = u.Id
    )
    left join PostLinksDuplicates pl on pl.PostId in (
        select p5.Id from Posts p5 where p5.OwnerUserId = u.Id
    )
    group by u.Id, u.DisplayName, u.Reputation, ps.QuestionCount, ps.AnswerCount, ps.AvgPostScore, ps.AcceptedAnswerCount, badges.BadgeCount, cd.CloseDate
),
UserPostsAndComments as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(p.NumPosts, 0) as PostCount,
        coalesce(c.NumComments, 0) as CommentCount,
        coalesce(p.NumPosts, 0) + coalesce(c.NumComments, 0) as TotalActivity
    from Users u
    left join (
        select OwnerUserId, count(*) as NumPosts
        from Posts
        group by OwnerUserId
    ) p on p.OwnerUserId = u.Id
    left join (
        select UserId, count(*) as NumComments
        from Comments
        group by UserId
    ) c on c.UserId = u.Id
),
UserRankings as (
    select *,
           rank() over (order by TotalActivity desc nulls last) as ActivityRank,
           rank() over (order by Reputation desc nulls last) as ReputationRank
    from UserPostsAndComments
)
select distinct
    u.Id,
    u.DisplayName,
    u.Reputation,
    ucs.QuestionCount,
    ucs.AnswerCount,
    ucs.AvgScore,
    ucs.AcceptedAnswers,
    ucs.TotalBadges,
    ucs.HasClosedPosts,
    ucs.MaxDuplicatesLinked,
    ucs.LatestPost,
    ur.TotalActivity,
    ur.ActivityRank,
    ur.ReputationRank,
    string_agg(distinct rt.FullPath, ' | ') filter (where rt.Depth >= 1) as RelatedTagPaths,
    coalesce(
        (select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 2),
        0
    ) as UpVoteCount,
    coalesce(
        (select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 3),
        0
    ) as DownVoteCount,
    coalesce(
        (select avg(length(p.Body)) from Posts p where p.OwnerUserId = u.Id and p.Body is not null),
        0
    ) as AvgBodyLength,
    case when u.Reputation > 10000 and coalesce(ucs.QuestionCount,0) > 50 then 'Veteran Expert'
         when u.Reputation > 5000 and coalesce(ucs.AnswerCount,0) > 100 then 'Prolific Answerer'
         else 'Normal User'
    end as UserCategory
from Users u
left join ComplexUserActivities ucs on ucs.Id = u.Id
left join UserRankings ur on ur.UserId = u.Id
left join Posts p on p.OwnerUserId = u.Id
left join RecursiveTagHierarchy rt on (p.Tags like '%' || rt.TagName || '%')
where u.Reputation > 1000
  and u.CreationDate < now() - interval '1 year'
  and (ucs.HasClosedPosts = 1 or ucs.AcceptedAnswers > 0)
order by ur.ActivityRank, u.Reputation desc
limit 20;