-- {"query": "436.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1587} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> all(r.Path)
    where t2.IsModeratorOnly = 0 and t2.Count > 10 and r.Level < 3
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as rn,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore,
        case when p.ViewCount > 1000 then 'HighView' else 'LowView' end as ViewCategory,
        coalesce(p.FavoriteCount,0) + coalesce(p.CommentCount,0) as EngagementScore
    from Posts p
    where p.PostTypeId in (1,2) and p.OwnerUserId is not null
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount,
        q.CreationDate as QuestionCreationDate,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwnerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.Body,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.Score > 10
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as PostOwner,
        u2.DisplayName as RelatedPostOwner
    from PostLinks pl
    left join Posts p on p.Id = pl.PostId
    left join Users u on u.Id = p.OwnerUserId
    left join Posts p2 on p2.Id = pl.RelatedPostId
    left join Users u2 on u2.Id = p2.OwnerUserId
    where pl.LinkTypeId = 3
),
CloseReasonCounts as (
    select
        pht.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory pht
    join CloseReasonTypes crt on crt.Id::varchar = pht.Comment
    where pht.PostHistoryTypeId = 10
    group by pht.Comment, crt.Name
),
UserEngagement as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as TotalUpVotes,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as TotalDownVotes,
        coalesce(sum(p.Score),0) as TotalPostScore,
        coalesce(sum(v.BountyAmount),0) as TotalBountyReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
ComplexUserMetrics as (
    select
        ue.Id,
        ue.DisplayName,
        ue.TotalPosts,
        ue.TotalComments,
        ue.TotalUpVotes,
        ue.TotalDownVotes,
        ue.TotalPostScore,
        ue.TotalBountyReceived,
        case
            when ue.TotalPosts = 0 then null
            else round(cast(ue.TotalPostScore as numeric) / ue.TotalPosts, 2)
        end as AvgScorePerPost,
        case
            when ue.TotalComments = 0 then null
            else round(cast(ue.TotalUpVotes as numeric) / ue.TotalComments, 2)
        end as UpVotesPerComment,
        case
            when ue.TotalPosts + ue.TotalComments = 0 then null
            else round(cast(ue.TotalBountyReceived as numeric) / (ue.TotalPosts + ue.TotalComments), 2)
        end as BountyPerActivity
    from UserEngagement ue
)
select
    c.Id as UserId,
    c.DisplayName,
    c.TotalPosts,
    c.TotalComments,
    c.TotalUpVotes,
    c.TotalDownVotes,
    c.TotalPostScore,
    c.TotalBountyReceived,
    c.AvgScorePerPost,
    c.UpVotesPerComment,
    c.BountyPerActivity,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.LastBadgeDate,
    dt.TagName as RequiredTagName,
    dt.Level as TagLevel,
    dt.Count as TagUsageCount,
    q.QuestionId,
    q.Title as QuestionTitle,
    q.QuestionScore,
    q.ViewCount as QuestionViews,
    q.QuestionCreationDate,
    a.AnswerId,
    a.AnswerOwnerUserId,
    a.AnswerScore,
    a.AnswerCreationDate,
    substring(a.Body from 1 for 100) as AnswerExcerpt,
    dl.PostId as DuplicatePostId,
    dl.RelatedPostId as DuplicateRelatedPostId,
    dl.PostOwner as DuplicatePostOwner,
    dl.RelatedPostOwner as DuplicateRelatedPostOwner,
    crc.CloseReasonName,
    crc.CloseCount
from ComplexUserMetrics c
left join UserBadgeStats ub on ub.UserId = c.Id
left join RecursiveTagHierarchy dt on dt.Level = 1
left join TopQuestionsWithAnswers q on q.OwnerUserId = c.Id and q.AnswerRank = 1
left join DuplicateLinks dl on dl.PostOwner = c.DisplayName
left join CloseReasonCounts crc on crc.CloseReasonId = '101' -- Duplicate close reason
where c.TotalPosts > 5
  and (c.AvgScorePerPost > 2 or c.BountyPerActivity > 0)
  and (dt.TagName is not null)
order by c.TotalPostScore desc, c.TotalUpVotes desc, q.QuestionScore desc
limit 100;