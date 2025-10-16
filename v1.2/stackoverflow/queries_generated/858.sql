-- {"query": "858.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1401} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        row_number() over (partition by t.Id order by p.Score desc nulls last, p.ViewCount desc nulls last) as rn
    from Tags t
    join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    where p.PostTypeId = 1 -- questions only
),
UserBadgeRank as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        dense_rank() over (partition by b.UserId order by b.Class) as ClassRank
    from Badges b
    group by b.UserId, b.Class
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        sum(v.VoteTypeId = 2::int)::int as UpVotesCount,
        sum(v.VoteTypeId = 3::int)::int as DownVotesCount,
        row_number() over (order by u.Reputation desc nulls last) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopScoredPosts as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        pt.Name as PostType,
        u.DisplayName as Owner,
        row_number() over (partition by p.PostTypeId order by p.Score desc nulls last, p.ViewCount desc nulls last) as RankWithinType
    from Posts p
    join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
    where p.Score is not null
),
AnswerWithAcceptedInfo as (
    select
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        case when q.AcceptedAnswerId = a.Id then 1 else 0 end as IsAccepted,
        q.Title as QuestionTitle,
        u.DisplayName as AnswererName
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then crt.Name else null end) as CloseReason,
        max(ph.CreationDate) as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) and ph.PostHistoryTypeId = 10
    group by ph.PostId
),
UserReputationRankings as (
    select
        Id,
        DisplayName,
        Reputation,
        rank() over (order by Reputation desc nulls last) as ReputationRank
    from Users
),
PostVotesAgg as (
    select
        p.Id as PostId,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as UpVotes,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as DownVotes,
        coalesce(sum(case when v.VoteTypeId = 5 then 1 else 0 end),0) as Favorites
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
)
select distinct
    uaw.Id as UserId,
    uaw.DisplayName as UserName,
    uaw.Reputation,
    uaw.QuestionCount,
    uaw.AnswerCount,
    uaw.CommentCount,
    uaw.UpVotesCount,
    uaw.DownVotesCount,
    ub.Class as BadgeClass,
    ub.BadgeCount,
    rtc.TagName,
    rtc.Count as TagPopularity,
    rtc.PostId as TaggedPostId,
    rtc.Score as TaggedPostScore,
    ts.Title as TopPostTitle,
    ts.Score as TopPostScore,
    ts.ViewCount as TopPostViews,
    ts.PostType as TopPostType,
    awai.Id as AnswerId,
    awai.IsAccepted,
    awai.Score as AnswerScore,
    awai.QuestionTitle,
    awai.AnswererName,
    cqwr.CloseReason,
    cqwr.CloseDate,
    urr.ReputationRank,
    pva.UpVotes,
    pva.DownVotes,
    pva.Favorites,
    case 
      when ts.Score > 10 and pva.Favorites > 5 and uaw.Reputation > 1000 then 'High Impact User'
      when uaw.Reputation between 500 and 1000 then 'Medium Impact User'
      else 'Low Impact User'
    end as UserImpactCategory,
    case when uaw.DisplayName is null then 'Anonymous' else concat('User: ', uaw.DisplayName) end as UserLabel,
    concat_ws(' | ', ts.Title, awai.QuestionTitle, rtc.TagName) as CompositeLabel
from UserActivityWindow uaw
left join UserBadgeRank ub on ub.UserId = uaw.Id and ub.ClassRank = 1
left join RecursiveTagCounts rtc on rtc.OwnerUserId = uaw.Id and rtc.rn = 1
left join TopScoredPosts ts on ts.Owner = uaw.DisplayName and ts.RankWithinType = 1
left join AnswerWithAcceptedInfo awai on awai.OwnerUserId = uaw.Id and awai.Score > 5
left join ClosedQuestionsWithReasons cqwr on cqwr.PostId = awai.ParentId
left join UserReputationRankings urr on urr.Id = uaw.Id
left join PostVotesAgg pva on pva.PostId = coalesce(ts.Id, awai.Id)
where uaw.Reputation > 100
order by uaw.Reputation desc nulls last, ts.Score desc nulls last
limit 100;