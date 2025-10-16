-- {"query": "1396.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1384} 
with recursive TagTree as (
    select t.Id, t.TagName, t.Count, 1 as Level
    from Tags t
    where t.Count > 1000
    union all
    select t2.Id, t2.TagName, t2.Count, tt.Level + 1
    from Tags t2
    join TagTree tt on t2.Count < tt.Count and t2.Count > tt.Count / 10
    where tt.Level < 3
),
UserBadgesCount as (
    select UserId,
           count(case when Class = 1 then 1 end) as GoldBadges,
           count(case when Class = 2 then 1 end) as SilverBadges,
           count(case when Class = 3 then 1 end) as BronzeBadges,
           count(*) as TotalBadges
    from Badges
    group by UserId
),
PostScoreWithVotes as (
    select p.Id, p.PostTypeId, p.OwnerUserId,
           p.Score,
           coalesce((select sum(case when VoteTypeId = 2 then 1 when VoteTypeId = 3 then -1 else 0 end)
                     from Votes v where v.PostId = p.Id), 0) as VoteScore
    from Posts p
    where p.PostTypeId in (1, 2)
),
WindowedPosts as (
    select p.Id, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.OwnerUserId,
           row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.ViewCount desc nulls last) as PostRank,
           rank() over (order by p.CreationDate) as CreationRank
    from Posts p
    where p.PostTypeId = 1
),
PostWithCloseInfo as (
    select p.Id, p.Title, p.Tags, p.ClosedDate, ph.Comment as CloseReasonComment,
           crt.Name as CloseReasonName
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as smallint)
    where p.PostTypeId = 1 and p.ClosedDate is not null
),
CorrelatedCommentsCount as (
    select p.Id, p.Title,
           (select count(*) from Comments c where c.PostId = p.Id and c.CreationDate >= p.CreationDate) as RecentCommentCount
    from Posts p
    where p.PostTypeId = 1
),
TagsWithPosts as (
    select tt.TagName, count(distinct p.Id) as NumPosts,
           avg(p.Score) as AvgScore,
           sum(p.ViewCount) as TotalViews,
           string_agg(distinct u.DisplayName, ', ' order by u.DisplayName) as OwnerUserNames
    from TagTree tt
    join Posts p on p.Tags like '%' || concat('<', tt.TagName, '>') || '%'
    left join Users u on u.Id = p.OwnerUserId
    group by tt.TagName
),
AnswersWithParentInfo as (
    select a.Id as AnswerId, a.ParentId as QuestionId, q.Title as QuestionTitle, q.Tags as QuestionTags,
           a.Score as AnswerScore, a.CreationDate as AnswerCreationDate,
           u.DisplayName as OwnerDisplayName,
           (select max(Score) from Posts where ParentId = a.ParentId and PostTypeId = 2) as MaxAnswerScoreForQuestion
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
QualifiedBadgedUsers as (
    select u.Id, u.DisplayName, ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges,
           row_number() over (order by ubc.GoldBadges desc, ubc.SilverBadges desc, ubc.BronzeBadges desc) as BadgeRank
    from Users u
    join UserBadgesCount ubc on ubc.UserId = u.Id
    where ubc.GoldBadges >= 5 and u.Reputation > 1000
)
select distinct
       p.Id as QuestionId,
       p.Title,
       p.Tags,
       p.CreationDate,
       p.Score as QuestionScore,
       p.ViewCount,
       p.AnswerCount,
       pwv.VoteScore as QuestionVoteScore,
       nws.PostRank,
       p.CloseReasonName,
       mer.MaxAnswerId,
       mer.MaxAnswerScore,
       mer.MaxAnswerOwner,
       corComments.RecentCommentCount,
       qua.DisplayName as TopBadgeUser,
       qua.GoldBadges, qua.SilverBadges, qua.BronzeBadges
from Posts p
join PostScoreWithVotes pwv on pwv.Id = p.Id
left join WindowedPosts nws on nws.Id = p.Id
left join PostWithCloseInfo psi on psi.Id = p.Id
left join CorrelatedCommentsCount corComments on corComments.Id = p.Id
left join QualifiedBadgedUsers qua on qua.Id = p.OwnerUserId
left join lateral (
    select gotMax.AnswerId, gotMax.AnswerScore, gotMax.OwnerName as MaxAnswerOwner
    from (
        select a.AnswerId, a.AnswerScore, a.OwnerDisplayName as OwnerName,
               rank() over (order by a.AnswerScore desc nulls last, a.AnswerId) as rank_asc
        from AnswersWithParentInfo a
        where a.QuestionId = p.Id
    ) gotMax
    where gotMax.rank_asc = 1
    limit 1
) mer on true
where p.PostTypeId = 1
and p.CreationDate > (current_date - interval '1 year')
and (p.Score + pwv.VoteScore) >= 5
and (p.ViewCount is not null and p.ViewCount > 100)
and (psi.ClosedDate is null or psi.ClosedDate > (current_date - interval '30 days'))
and (
    select count(*)
    from Comments c2
    where c2.PostId = p.Id
      and c2.Text ILIKE '%performance%'
) > 0 -- question with performance in comments at least once
order by p.Score desc nulls last, p.ViewCount desc nulls last
limit 25;