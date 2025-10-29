-- {"query": "2909.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1408} 
with RecursiveBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopPosts as (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    where p.PostTypeId = 1
      and p.Score is not null
      and p.ViewCount is not null
),
RecentActivityCTE as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastEditDate,
        count(distinct ph.UserId) as DistinctEditors,
        string_agg(distinct ph.UserDisplayName, ', ' order by ph.UserDisplayName) as EditorsList
    from PostHistory ph
    where ph.PostId in (select Id from Posts where PostTypeId = 1)
      and ph.PostHistoryTypeId in (4,5,6,7,8,9)
    group by ph.PostId
),
PostCommentStats as (
    select
        c.PostId,
        count(c.Id) as TotalComments,
        count(distinct c.UserId) as DistinctCommenters,
        max(c.CreationDate) as LastCommentDate,
        sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments
    from Comments c
    group by c.PostId
),
DuplicateLinkCounts as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
),
TopAnswers as (
    select
        a.ParentId as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwner,
        rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
UserEngagement as (
    select
        u.Id as UserId,
        coalesce(sum(vt.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vt.DownVotes),0) as TotalDownVotes,
        count(distinct b.Id) as BadgesCount,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        count(distinct c.Id) as CommentsCount,
        (coalesce(sum(vt.UpVotes),0) - coalesce(sum(vt.DownVotes),0)) as NetVotes
    from Users u
    left join (
        select OwnerUserId, sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes, sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        where p.OwnerUserId is not null
        group by OwnerUserId
    ) vt on vt.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    rbc.GoldBadges,
    rbc.SilverBadges,
    rbc.BronzeBadges,
    ts.Title as TopQuestionTitle,
    ts.Score as TopQuestionScore,
    ts.ViewCount as TopQuestionViewCount,
    coalesce(dlc.DuplicateCount,0) as NumberOfDuplicates,
    rac.DistinctEditors,
    rac.LastEditDate,
    pcs.TotalComments,
    pcs.PositiveComments,
    ac.AnswerId as HighestScoreAnswerId,
    ac.AnswerScore as HighestAnswerScore,
    ac.AnswerOwner as HighestAnswerOwner,
    ue.TotalUpVotes,
    ue.TotalDownVotes,
    ue.NetVotes,
    ue.QuestionsCount,
    ue.AnswersCount,
    ue.CommentsCount,
    case 
        when u.Location is not null and length(trim(u.Location)) > 0 then upper(trim(u.Location))
        else 'UNKNOWN'
    end as LocationNormalized,
    case 
        when u.WebsiteUrl like '%stackoverflow.com%' then 'StackOverflow User'
        when u.WebsiteUrl is not null then 'Other Site User'
        else 'No Website'
    end as WebsiteCategory
from Users u
inner join RecursiveBadgeCounts rbc on rbc.UserId = u.Id
left join TopPosts ts on ts.OwnerUserId = u.Id and ts.rn = 1
left join RecentActivityCTE rac on rac.PostId = ts.Id
left join PostCommentStats pcs on pcs.PostId = ts.Id
left join DuplicateLinkCounts dlc on dlc.PostId = ts.Id
left join TopAnswers ac on ac.QuestionId = ts.Id and ac.AnswerRank = 1
left join UserEngagement ue on ue.UserId = u.Id
where u.Reputation > (
    select percentile_cont(0.75) within group (order by Reputation) from Users
)
and (
    ts.Score > 10
    or pcs.TotalComments > 5
)
and (
    exists (
        select 1 from PostHistory ph2 
        where ph2.PostId = ts.Id
          and ph2.PostHistoryTypeId = 10
          and ph2.CreationDate > current_date - interval '1 year'
    )
    or coalesce(dlc.DuplicateCount, 0) > 2
)
order by ue.NetVotes desc nulls last, rbc.GoldBadges desc, ts.Score desc
limit 100;