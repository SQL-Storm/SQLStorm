-- {"query": "2618.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1304} 
with recursive TagHierarchy as (
    select t.Id, t.TagName, t.Count, 1 as Level, array[t.Id] as Path
    from Tags t
    where not t.TagName is null
  union all
    select t2.Id, t2.TagName, t2.Count, th.Level + 1, path || t2.Id
    from Tags t2
    join TagHierarchy th on t2.Count < th.Count and not t2.Id = any(th.Path)
    where th.Level < 3
),
UserBadgeStats as (
    select u.Id as UserId, u.DisplayName,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionAnswerStats as (
    select q.Id as QuestionId, q.Title, q.OwnerUserId, q.CreationDate as QuestionCreation,
           a.Id as AnswerId, a.OwnerUserId as AnswerOwner, a.CreationDate as AnswerCreation,
           a.Score as AnswerScore,
           row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
TopAnswersWithComments as (
    select qa.QuestionId, qa.Title, qa.AnswerId, qa.AnswerOwner, qa.AnswerScore, qa.AnswerCreation,
           c.Id as CommentId, c.Text as CommentText,
           row_number() over (partition by qa.AnswerId order by c.CreationDate desc) as CommentRank
    from QuestionAnswerStats qa
    left join Comments c on c.PostId = qa.AnswerId
    where qa.AnswerRank = 1
),
FilteredPostHistories as (
    select ph.PostId, ph.PostHistoryTypeId, pht.Name as HistoryTypeName,
           ph.CreationDate, ph.UserId, ph.UserDisplayName,
           ph.Comment, ph.Text,
           row_number() over (partition by ph.PostId, ph.PostHistoryTypeId order by ph.CreationDate desc) as RevRank
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    where ph.PostHistoryTypeId in (10,11,12,13) -- Closed, Reopened, Deleted, Undeleted
),
LatestPostClosures as (
    select distinct on (ph.PostId) ph.PostId, ph.CreationDate, ph.UserId, ph.Comment as CloseReasonId
    from FilteredPostHistories ph
    where ph.PostHistoryTypeId = 10
    order by ph.PostId, ph.CreationDate desc
),
UserActivityWindows as (
    select u.Id as UserId, u.DisplayName, u.Reputation,
           count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
           count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
           max(p.CreationDate) over (partition by u.Id) as LastPostDate,
           min(p.CreationDate) over (partition by u.Id) as FirstPostDate,
           lead(u.LastAccessDate) over (order by u.LastAccessDate desc) as PrevUserLastAccess
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
DuplicateLinkCounts as (
    select pl.PostId, count(*) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
)
select ua.UserId, ua.DisplayName, ua.Reputation, ua.QuestionsPosted, ua.AnswersGiven,
       ua.LastPostDate, ua.FirstPostDate,
       coalesce(dlc.DuplicateCount, 0) as DuplicateLinks,
       ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.TagBasedBadges,
       la.CloseReasonId,
       concat(
           'Q: ', coalesce(q.Title, 'N/A'),
           ' | A: ', coalesce(cast(ta.AnswerId as varchar), 'N/A'),
           ' | Score: ', coalesce(cast(ta.AnswerScore as varchar), '0'),
           ' | Comment: ', coalesce(left(ta.CommentText, 50), 'No comments')
       ) as Summary,
       th.Level as TagLevel, th.TagName,
       case when ubs.GoldBadges > 0 then 'Senior' else 'Junior' end as UserSeniority
from UserActivityWindows ua
left join UserBadgeStats ubs on ubs.UserId = ua.UserId
left join LatestPostClosures la on la.UserId = ua.UserId
left join (
    select qas.QuestionId, qas.Title, max(qas.AnswerScore) as MaxAnswerScore
    from QuestionAnswerStats qas group by qas.QuestionId, qas.Title
) q on q.QuestionId in (
    select p.Id from Posts p where p.OwnerUserId = ua.UserId and p.PostTypeId = 1
)
left join TopAnswersWithComments ta on ta.QuestionId = q.QuestionId
left join DuplicateLinkCounts dlc on dlc.PostId = q.QuestionId
left join TagHierarchy th on th.TagName = substring(q.Title from '%#"(\\w+)"#%')
where ua.Reputation > 1000
  and (ua.LastPostDate >= (now() - interval '1 year') or ua.LastPostDate is null)
order by ua.Reputation desc, ua.LastPostDate desc
limit 100;