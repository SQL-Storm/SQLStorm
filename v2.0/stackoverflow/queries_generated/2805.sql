-- {"query": "2805.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1566} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        coalesce(t.Count, 0) as TagCount,
        1 as Level,
        cast(t.TagName as varchar(1000)) as TagPath
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select 
        t2.Id,
        t2.TagName,
        coalesce(t2.Count, 0),
        r.Level + 1,
        cast(r.TagPath || ' > ' || t2.TagName as varchar(1000))
    from Tags t2
    inner join RecursiveTagHierarchy r on length(t2.TagName) > length(r.TagName) and substr(t2.TagName,1,length(r.TagName)) = r.TagName
    where r.Level < 3
),
PostStats as (
    select 
       p.Id as PostId,
       p.PostTypeId,
       p.CreationDate,
       p.Score,
       p.ViewCount,
       p.OwnerUserId,
       p.AcceptedAnswerId,
       p.Title,
       p.Tags,
       array_length(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'),1) as TagCount,
       row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as UserPostRank
    from Posts p
    where p.PostTypeId in (1,2) -- questions and answers
),
UserBadgesAgg as (
    select
       b.UserId,
       count(case when b.Class=1 then 1 end) as GoldBadges,
       count(case when b.Class=2 then 1 end) as SilverBadges,
       count(case when b.Class=3 then 1 end) as BronzeBadges,
       count(distinct b.Name) as DistinctBadges
    from Badges b
    group by b.UserId
),
UserActivityWindow as (
    select
       u.Id as UserId,
       count(distinct p.Id) as TotalPosts,
       count(distinct c.Id) as TotalComments,
       sum(vtUp.VoteCount) as TotalUpVotes,
       sum(vtDown.VoteCount) as TotalDownVotes,
       max(p.CreationDate) over (partition by u.Id) as LastPostDate,
       min(p.CreationDate) over (partition by u.Id) as FirstPostDate,
       array_agg(distinct t.TagName) filter (where t.TagName is not null) as UserTags
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes vtUp on vtUp.PostId = p.Id and vtUp.VoteTypeId = 2
    left join Votes vtDown on vtDown.PostId = p.Id and vtDown.VoteTypeId = 3
    left join (
       select unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) as TagName, p.Id as PostId
       from Posts p where p.PostTypeId = 1
    ) t on t.PostId = p.Id
    group by u.Id
),
UserReputationChanges as (
    select
        u.Id as UserId,
        sum(case when v.VoteTypeId = 2 then 10 else 0 end) - sum(case when v.VoteTypeId = 3 then 2 else 0 end) as ReputationScoreDelta,
        count(distinct v.Id) as TotalVotesCast,
        count(distinct case when v.VoteTypeId = 5 then v.Id end) as FavoriteVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id and v.UserId = u.Id
    group by u.Id
),
ClosedQuestionsWithReasons as (
    select distinct 
        ph.PostId,
        ph.Comment as CloseReasonCode,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
AnswersWithLinkDuplicates as (
    select distinct
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        pl.LinkTypeId,
        lt.Name as LinkTypeName,
        pl.RelatedPostId,
        p.Title as RelatedPostTitle
    from Posts a
    left join PostLinks pl on pl.PostId = a.Id and pl.LinkTypeId in (1,3)
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    left join Posts p on p.Id = pl.RelatedPostId
    where a.PostTypeId = 2
)
select 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    ua.TotalPosts,
    ua.TotalComments,
    coalesce(ub.GoldBadges,0) as GoldBadges,
    coalesce(ub.SilverBadges,0) as SilverBadges,
    coalesce(ub.BronzeBadges,0) as BronzeBadges,
    ua.LastPostDate,
    ua.FirstPostDate,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ur.ReputationScoreDelta,
    ur.TotalVotesCast,
    ur.FavoriteVotes,
    array_to_string(ua.UserTags, ', ') as UserTags,
    coalesce(ps.TagCount,0) as LatestPostTagCount,
    ps.Title as LatestPostTitle,
    cq.CloseReasonName,
    cq.CloseDate,
    array_agg(distinct adh.LinkTypeName || ': ' || coalesce(adh.RelatedPostTitle, 'N/A')) filter (where adh.QuestionId is not null) as AnswerLinkDetails,
    row_number() over (order by u.Reputation desc, ua.TotalPosts desc) as UserRank
from Users u
left join UserActivityWindow ua on ua.UserId = u.Id
left join UserBadgesAgg ub on ub.UserId = u.Id
left join UserReputationChanges ur on ur.UserId = u.Id
left join PostStats ps on ps.OwnerUserId = u.Id and ps.UserPostRank=1
left join ClosedQuestionsWithReasons cq on cq.PostId = ps.PostId and ps.PostTypeId=1
left join AnswersWithLinkDuplicates adh on adh.QuestionId = ps.PostId and ps.PostTypeId=1
where u.Reputation > 1000 and ua.TotalPosts > 20
group by u.Id, u.DisplayName, u.Reputation, ua.TotalPosts, ua.TotalComments, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ua.LastPostDate, ua.FirstPostDate, ua.TotalUpVotes, ua.TotalDownVotes, ur.ReputationScoreDelta, ur.TotalVotesCast, ur.FavoriteVotes, ua.UserTags, ps.TagCount, ps.Title, cq.CloseReasonName, cq.CloseDate
having sum(case when (coalesce(ub.GoldBadges,0) + coalesce(ub.SilverBadges,0) + coalesce(ub.BronzeBadges,0)) > 0 then 1 else 0 end) >= 1
order by UserRank
limit 50;