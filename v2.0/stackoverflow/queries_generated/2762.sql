-- {"query": "2762.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1800} 
with RecursiveTagExpansion as (
    select t.Id, t.TagName, 1 as Level
    from Tags t
    where t.IsRequired = 1
  union all
    select t2.Id, t2.TagName, rte.Level + 1
    from Tags t2
    join RecursiveTagExpansion rte on position(concat('<', t2.TagName, '>') in (
        select p.Tags from Posts p where p.Tags is not null and position(concat('<', rte.TagName, '>') in p.Tags) > 0 limit 1
    )) > 0
    where rte.Level < 3
),
UserBadgeCounts as (
    select u.Id as UserId, u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionStats as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        coalesce((select count(*) from Comments c where c.PostId = p.Id), 0) as CommentCount,
        coalesce(u.Reputation, 0) as OwnerReputation,
        u.DisplayName as OwnerName,
        row_number() over (order by p.Score desc, p.ViewCount desc) as RankByScore,
        dense_rank() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentQuestionsByOwner
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1  -- questions only
),
TopAnsweredQuestions as (
    select q.QuestionId, q.Title, q.AnswerCount, q.Score, q.ViewCount,
        case when q.AnswerCount > 0 then round(1.0 * q.ViewCount / q.AnswerCount, 2) else null end as ViewsPerAnswer,
        q.OwnerUserId, q.OwnerName, q.OwnerReputation,
        (select coalesce(max(a.Score), 0) from Posts a where a.ParentId = q.QuestionId) as HighestAnswerScore,
        (select count(distinct ph.PostId) from PostHistory ph where ph.PostId = q.QuestionId and ph.PostHistoryTypeId in (10, 11) /* Closed or Reopened */) as CloseReopenEvents,
        (select count(distinct v.Id) from Votes v where v.PostId = q.QuestionId and v.VoteTypeId = 5) as TotalFavorites, -- VoteTypeId 5 Favorite (legacy)
        q.CommentCount
    from QuestionStats q
    where q.AnswerCount >= 5
),
UserActivityWindow as (
    select u.Id, u.DisplayName, u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as QuestionsAsked30d,
        count(distinct p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as AnswersGiven30d,
        count(distinct b.Id) over (partition by u.Id order by b.Date range between interval '30 days' preceding and current row) as BadgesEarned30d
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
),
DistinctLinkedPosts as (
    select pl.PostId, pl.RelatedPostId, lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
),
HighImpactBadges as (
    select ubc.UserId, ubc.DisplayName, ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges
    from UserBadgeCounts ubc
    where ubc.GoldBadges > 10 or ubc.SilverBadges > 25
),
FinalDataset as (
    select 
        tq.QuestionId, tq.Title, tq.AnswerCount, tq.Score, tq.ViewCount, tq.ViewsPerAnswer, tq.OwnerUserId, tq.OwnerName, tq.OwnerReputation,
        tq.HighestAnswerScore, tq.CloseReopenEvents, tq.TotalFavorites, tq.CommentCount,
        hab.GoldBadges, hab.SilverBadges, hab.BronzeBadges,
        ua.QuestionsAsked30d, ua.AnswersGiven30d, ua.BadgesEarned30d,
        string_agg(distinct dlp.LinkTypeName, ', ') as LinkTypes
    from TopAnsweredQuestions tq
    left join HighImpactBadges hab on hab.UserId = tq.OwnerUserId
    left join UserActivityWindow ua on ua.Id = tq.OwnerUserId
    left join DistinctLinkedPosts dlp on dlp.PostId = tq.QuestionId
    group by tq.QuestionId, tq.Title, tq.AnswerCount, tq.Score, tq.ViewCount, tq.ViewsPerAnswer, tq.OwnerUserId, tq.OwnerName, tq.OwnerReputation,
             tq.HighestAnswerScore, tq.CloseReopenEvents, tq.TotalFavorites, tq.CommentCount,
             hab.GoldBadges, hab.SilverBadges, hab.BronzeBadges,
             ua.QuestionsAsked30d, ua.AnswersGiven30d, ua.BadgesEarned30d
)
select
    fd.QuestionId,
    fd.Title,
    fd.OwnerName,
    fd.OwnerReputation,
    fd.Score,
    fd.ViewCount,
    fd.AnswerCount,
    fd.ViewsPerAnswer,
    coalesce(fd.HighestAnswerScore, 0) as HighestAnswerScore,
    fd.CloseReopenEvents,
    fd.TotalFavorites,
    fd.CommentCount,
    coalesce(fd.GoldBadges, 0) as GoldBadges,
    coalesce(fd.SilverBadges, 0) as SilverBadges,
    coalesce(fd.BronzeBadges, 0) as BronzeBadges,
    coalesce(fd.QuestionsAsked30d, 0) as QuestionsAskedLast30Days,
    coalesce(fd.AnswersGiven30d, 0) as AnswersGivenLast30Days,
    coalesce(fd.BadgesEarned30d, 0) as BadgesEarnedLast30Days,
    coalesce(fd.LinkTypes, 'None') as LinkTypes,
    case
        when fd.Score >= 100 and fd.ViewCount >= 10000 then 'High Engagement'
        when fd.Score >= 50 then 'Medium Engagement'
        else 'Low Engagement'
    end as EngagementCategory,
    -- Complex string expression for tag extraction
    (
      select string_agg(distinct unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2),'><')), ', ')
      from Posts p
      where p.Id = fd.QuestionId and p.Tags is not null
    ) as TagsList,
    -- Correlated subquery to find the earliest post history edit for the question
    (
      select min(ph.CreationDate)
      from PostHistory ph
      where ph.PostId = fd.QuestionId and ph.PostHistoryTypeId in (4,5,6) -- edits to title, body, tags
    ) as FirstEditDate,
    -- Null logic with coalesce and conditional
    coalesce(
      (
        select max(ph.CreationDate)
        from PostHistory ph
        where ph.PostId = fd.QuestionId
          and ph.PostHistoryTypeId = 10 -- Post Closed
      ),
      '2100-01-01'::timestamp
    ) as LastClosedDate,
    -- Window aggregate for ranking within the same owner by score and date
    rank() over (partition by fd.OwnerUserId order by fd.Score desc, fd.ViewCount desc) as OwnerPostRank
from FinalDataset fd
where fd.AnswerCount >= 10
  and (fd.OwnerReputation > 1000 or fd.GoldBadges >= 5)
order by fd.Score desc, fd.ViewCount desc
limit 100;