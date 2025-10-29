-- {"query": "2876.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1631} 
with RecursiveUserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Class,
        count(b.Id) as BadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, b.Class
), RankedPosts as (
    select
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AcceptedAnswerId,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc nulls last) as ScoreRank,
        row_number() over (partition by p.OwnerUserId order by p.ViewCount desc nulls last) as ViewRank
    from Posts p
    where p.PostTypeId in (1, 2)
), TopUserPosts as (
    select
        rp.*
    from RankedPosts rp
    where rp.ScoreRank <= 3 or rp.ViewRank <= 3
), BadgeSummary as (
    select
        UserId,
        sum(case when Class = 1 then BadgeCount else 0 end) as GoldBadges,
        sum(case when Class = 2 then BadgeCount else 0 end) as SilverBadges,
        sum(case when Class = 3 then BadgeCount else 0 end) as BronzeBadges
    from RecursiveUserBadgeCounts
    group by UserId
), QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.OwnerUserId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        count(a.Id) filter (where a.PostTypeId = 2) as AnswerCount,
        max(a.Score) filter (where a.PostTypeId = 2) as MaxAnswerScore,
        avg(a.Score)::numeric(10,2) filter (where a.PostTypeId = 2) as AvgAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.OwnerUserId, q.Title, q.Tags, q.Score, q.ViewCount
), TopQuestionsWithUserBadges as (
    select
        qas.QuestionId,
        qas.Title,
        qas.Tags,
        qas.QuestionScore,
        qas.QuestionViews,
        qas.AnswerCount,
        qas.MaxAnswerScore,
        qas.AvgAnswerScore,
        coalesce(bs.GoldBadges, 0) as GoldBadges,
        coalesce(bs.SilverBadges, 0) as SilverBadges,
        coalesce(bs.BronzeBadges, 0) as BronzeBadges,
        u.DisplayName as QuestionOwner,
        u.Reputation as QuestionOwnerReputation
    from QuestionAnswerStats qas
    left join BadgeSummary bs on bs.UserId = qas.OwnerUserId
    left join Users u on u.Id = qas.OwnerUserId
    where qas.AnswerCount > 0
), LatestCloseReasons as (
    select distinct on (ph.PostId)
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    inner join CloseReasonTypes crt on ph.Comment::int = crt.Id
    where ph.PostHistoryTypeId = 10
    order by ph.PostId, ph.CreationDate desc
), UsersWithCommentsCount as (
    select
        u.Id,
        u.DisplayName,
        count(c.Id) as CommentCount
    from Users u
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName
), CombinedUserStats as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(uwc.CommentCount, 0) as CommentCount,
        coalesce(bs.GoldBadges, 0) as GoldBadges,
        coalesce(bs.SilverBadges, 0) as SilverBadges,
        coalesce(bs.BronzeBadges, 0) as BronzeBadges,
        row_number() over (order by u.Reputation desc, coalesce(bs.GoldBadges,0) desc, coalesce(bs.SilverBadges,0) desc) as UserRanking
    from Users u
    left join UsersWithCommentsCount uwc on uwc.Id = u.Id
    left join BadgeSummary bs on bs.UserId = u.Id
    where u.Reputation > 1000
)
select
    tq.UserRanking,
    tq.DisplayName as UserName,
    tq.Reputation,
    tq.CommentCount,
    tq.GoldBadges,
    tq.SilverBadges,
    tq.BronzeBadges,
    qwtq.QuestionId,
    qwtq.Title,
    qwtq.Tags,
    qwtq.QuestionScore,
    qwtq.QuestionViews,
    qwtq.AnswerCount,
    qwtq.MaxAnswerScore,
    qwtq.AvgAnswerScore,
    lcr.CloseReasonName,
    -- Complex calculation for popularity metric
    round(
        (qwtq.QuestionScore * 0.5 + qwtq.MaxAnswerScore * 0.3 + qwtq.AvgAnswerScore * 0.1 + qwtq.QuestionViews * 0.1) * 
        (1 + tq.GoldBadges * 0.15 + tq.SilverBadges * 0.10 + tq.BronzeBadges * 0.05) , 2
    ) as PopularityScore,
    -- String manipulation on tags: get first tag if exists
    substring(split_part(trim(both '<>' from qwtq.Tags), '><', 1) from 1 for 30) as PrimaryTag,
    -- Conditional string expression on CloseReasonName with NULL handling
    coalesce(lcr.CloseReasonName, 'Open') as PostStatus
from CombinedUserStats tq
join TopQuestionsWithUserBadges qwtq on qwtq.QuestionOwner = tq.DisplayName
left join LatestCloseReasons lcr on lcr.PostId = qwtq.QuestionId
where qwtq.QuestionViews > 1000
union
-- Include some posts where questions had no answers but high view count and highlight new users
select
    null as UserRanking,
    u.DisplayName as UserName,
    u.Reputation,
    0 as CommentCount,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    p.Id as QuestionId,
    p.Title,
    p.Tags,
    p.Score as QuestionScore,
    p.ViewCount as QuestionViews,
    0 as AnswerCount,
    NULL as MaxAnswerScore,
    NULL as AvgAnswerScore,
    'Open' as CloseReasonName,
    (p.Score * 0.7 + p.ViewCount * 0.3) as PopularityScore,
    substring(split_part(trim(both '<>' from p.Tags), '><', 1) from 1 for 30) as PrimaryTag,
    'Open' as PostStatus
from Posts p
left join Users u on u.Id = p.OwnerUserId
where p.PostTypeId = 1
  and p.AnswerCount = 0
  and p.ViewCount > 5000
  and (u.CreationDate > now() - interval '180 days' or u.Id is null)
order by PopularityScore desc
limit 100;