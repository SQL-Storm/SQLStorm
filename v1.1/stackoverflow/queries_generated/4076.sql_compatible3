with RECURSIVE RecursiveTags as (
    select
        p.Id as PostId,
        unnest(string_to_array(trim(both '<>' from p.Tags), '><')) as Tag,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null

    union all

    select
        rt.PostId,
        t.TagName,
        rt.CreationDate,
        rt.Score,
        rt.ViewCount,
        rt.OwnerUserId
    from RecursiveTags rt
    join Tags t on rt.Tag = t.TagName
    where length(rt.Tag) < 3
),
UserBadgesAgg as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        bool_or(b.TagBased) as HasTagBasedBadges
    from Badges b
    group by b.UserId, b.Class
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        row_number() over (partition by u.Location order by u.Reputation desc) as LocRank,
        count(*) over (partition by u.Location) as LocUserCount
    from Users u
    where u.Location is not null
),
ClosedPosts AS (
    select
      p.Id,
      p.Title,
      p.Tags,
      p.OwnerUserId,
      ph.Comment as CloseReasonId,
      crt.Name as CloseReasonName,
      p.ClosedDate,
      p.Score
    from Posts p
    left join PostHistory ph on p.Id = ph.PostId and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where p.ClosedDate is not null
),
HighScoreAnswers AS (
    select
        a.Id,
        a.ParentId,
        a.Score,
        a.ViewCount,
        a.OwnerUserId,
        u.Reputation as OwnerReputation,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2 and a.Score > 10
),
QuestionsWithAcceptedAnswerScores AS (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        coalesce(aa.Score, 0) as AcceptedAnswerScore,
        coalesce(aa.OwnerUserId, -1) as AcceptedAnswerUserId,
        coalesce(aa.OwnerReputation, 0) as AcceptedAnswerUserReputation
    from Posts q
    left join (
        select a.Id, a.ParentId, a.Score, a.OwnerUserId, u.Reputation as OwnerReputation from Posts a
        join Users u on a.OwnerUserId = u.Id
        where a.PostTypeId = 2
    ) aa on q.AcceptedAnswerId = aa.Id
    where q.PostTypeId = 1
),
TagCounts AS (
    select Tag, count(distinct PostId) as PostCount
    from RecursiveTags
    group by Tag
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Location,
    ubg.BadgeCount,
    ubg.Class as BadgeClass,
    ubg.HasTagBasedBadges,
    qwa.QuestionId,
    qwa.Title as QuestionTitle,
    qwa.QuestionScore,
    qwa.QuestionViews,
    qwa.AcceptedAnswerScore,
    qwa.AcceptedAnswerUserReputation,
    cpt.CloseReasonName,
    count(distinct ca.Id) as ClosingCommentsCount,
    string_agg(distinct concat(rt.Tag, ':', cast(tc.PostCount as varchar)), ',' ) as PopularTags,
    max(case when hsa.OwnerUserId = u.Id then hsa.Score end) as MaxHighScoreAnswer,
    ua.LocRank,
    ua.LocUserCount
from Users u
left join UserBadgesAgg ubg on u.Id = ubg.UserId
left join QuestionsWithAcceptedAnswerScores qwa on u.Id = qwa.OwnerUserId
left join ClosedPosts cpt on cpt.OwnerUserId = u.Id
left join Comments ca on ca.PostId = cpt.Id and ca.CreationDate > cpt.ClosedDate - interval '30 days'
left join RecursiveTags rt on rt.OwnerUserId = u.Id
left join TagCounts tc on tc.Tag = rt.Tag
left join HighScoreAnswers hsa on hsa.OwnerUserId = u.Id
left join UserActivityWindow ua on ua.Id = u.Id
where u.Reputation > (
    select avg(Reputation) from Users where Location = u.Location
)
and (
    qwa.QuestionScore > 5 or qwa.AcceptedAnswerScore > 10 or ubg.BadgeCount > 2
)
group by
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Location,
    ubg.BadgeCount,
    ubg.Class,
    ubg.HasTagBasedBadges,
    qwa.QuestionId,
    qwa.Title,
    qwa.QuestionScore,
    qwa.QuestionViews,
    qwa.AcceptedAnswerScore,
    qwa.AcceptedAnswerUserReputation,
    cpt.CloseReasonName,
    ua.LocRank,
    ua.LocUserCount
having count(distinct ca.Id) > 0
order by u.Reputation desc, MaxHighScoreAnswer desc NULLS LAST
limit 100;