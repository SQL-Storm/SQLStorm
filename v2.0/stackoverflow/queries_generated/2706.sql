-- {"query": "2706.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1669} 
with RecursiveUserActivity as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score), 0) as TotalPostScore,
        coalesce(sum(vote_up.UpVotes), 0) as UpVotesReceived,
        coalesce(sum(vote_down.DownVotes), 0) as DownVotesReceived,
        coalesce(badge_counts.GoldBadges, 0) as GoldBadges,
        coalesce(badge_counts.SilverBadges, 0) as SilverBadges,
        coalesce(badge_counts.BronzeBadges, 0) as BronzeBadges,
        row_number() over (order by u.Reputation desc NULLS LAST, u.LastAccessDate desc NULLS LAST) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select v.PostId, count(*) as UpVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId and vt.Name = 'UpMod'
        group by v.PostId
    ) vote_up on vote_up.PostId = p.Id
    left join (
        select v.PostId, count(*) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId and vt.Name = 'DownMod'
        group by v.PostId
    ) vote_down on vote_down.PostId = p.Id
    left join (
        select 
            UserId,
            count(case when Class = 1 then 1 end) as GoldBadges,
            count(case when Class = 2 then 1 end) as SilverBadges,
            count(case when Class = 3 then 1 end) as BronzeBadges
        from Badges
        group by UserId
    ) badge_counts on badge_counts.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, 
             badge_counts.GoldBadges, badge_counts.SilverBadges, badge_counts.BronzeBadges
),
TopTaggedQuestions as (
    select distinct on (pt.Id)
        pt.Id as PostId, pt.Title, pt.OwnerUserId, pt.CreationDate,
        array_to_string(regexp_matches(pt.Tags, '<([^>]+)>', 'g'), ', ') as TagsList,
        pt.Score,
        count(distinct a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        (
            select count(*)
            from Comments c 
            where c.PostId = pt.Id and c.CreationDate > pt.CreationDate - interval '30 days'
        ) as RecentCommentCount
    from Posts pt
    left join Posts a on a.ParentId = pt.Id and a.PostTypeId = 2
    where pt.PostTypeId = 1
      and pt.Tags is not null
      and pt.Score > 5
      and pt.CreationDate > now() - interval '2 years'
    group by pt.Id, pt.Title, pt.OwnerUserId, pt.CreationDate, pt.Tags
    order by pt.Id, pt.Score desc
),
DuplicateLinkedPosts as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        lt.Name as LinkTypeName
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
PostEditHeatmap as (
    select ph.PostId,
           date_trunc('month', ph.CreationDate) as EditMonth,
           count(*) as EditsInMonth
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- edits to Title, Body, Tags
    group by ph.PostId, date_trunc('month', ph.CreationDate)
),
UserBadgesWithNullLogic as (
    select u.Id as UserId, u.DisplayName,
           coalesce(sum(case when b.Class = 1 then 1 else 0 end), 0) as Golds,
           coalesce(sum(case when b.Class = 2 then 1 else 0 end), 0) as Silvers,
           coalesce(sum(case when b.Class = 3 then 1 else 0 end), 0) as Bronzes,
           case when count(b.Id) = 0 then 'No Badges' else 'Has Badges' end as BadgeStatus
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
UserCommentActivity as (
    select c.UserId,
           count(*) as TotalComments,
           count(distinct c.PostId) as DistinctPostsCommented,
           max(c.CreationDate) as LastCommentDate,
           bool_or(c.Text ilike '%help%') as HasHelpTerm
    from Comments c
    group by c.UserId
),
RankedAnswersWithWindow as (
    select a.Id, a.ParentId as QuestionId, a.Score, a.CreationDate, a.OwnerUserId,
           row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
           nth_value(a.Score, 2) over (partition by a.ParentId order by a.Score desc) as SecondHighestScore
    from Posts a
    where a.PostTypeId = 2
)

select 
    ru.Id as UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.TotalPostScore,
    ru.UpVotesReceived,
    ru.DownVotesReceived,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.ReputationRank,
    tq.PostId as TopQuestionId,
    tq.Title as TopQuestionTitle,
    tq.TagsList as TopQuestionTags,
    tq.Score as TopQuestionScore,
    tq.AnswerCount as TopQuestionAnswerCount,
    tq.MaxAnswerScore as TopQuestionMaxAnswerScore,
    tq.RecentCommentCount as TopQuestionRecentComments,
    dup.PostTitle as DuplicatePostTitle,
    dup.RelatedPostTitle as DuplicateRelatedTitle,
    dup.LinkTypeName as DuplicateLinkType,
    ph.EditMonth,
    ph.EditsInMonth,
    ub.BadgeStatus,
    uc.TotalComments,
    uc.DistinctPostsCommented,
    uc.LastCommentDate,
    uc.HasHelpTerm,
    ra.AnswerRank,
    ra.SecondHighestScore,
    (ra.Score - ra.SecondHighestScore) as ScoreDifferenceWithSecond
from RecursiveUserActivity ru
left join TopTaggedQuestions tq on tq.OwnerUserId = ru.Id
left join DuplicateLinkedPosts dup on dup.PostId = tq.PostId
left join PostEditHeatmap ph on ph.PostId = tq.PostId and ph.EditMonth > now() - interval '12 months'
left join UserBadgesWithNullLogic ub on ub.UserId = ru.Id
left join UserCommentActivity uc on uc.UserId = ru.Id
left join RankedAnswersWithWindow ra on ra.OwnerUserId = ru.Id
where ru.Reputation > 10000
  and ub.BadgeStatus = 'Has Badges'
  and (uc.HasHelpTerm = true or uc.HasHelpTerm is null)
order by ru.ReputationRank
limit 50;