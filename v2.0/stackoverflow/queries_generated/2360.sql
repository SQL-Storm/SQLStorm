-- {"query": "2360.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1804} 
with recursive TagHierarchy as (
    select t.Id, t.TagName, t.Count, 1 as Level
    from Tags t
    where t.Count > 1000
  union all
    select t2.Id, t2.TagName, t2.Count, th.Level + 1
    from Tags t2
    join TagHierarchy th on length(t2.TagName) > length(th.TagName)
       and substring(t2.TagName from 1 for length(th.TagName)) = th.TagName
       and th.Level < 3
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(v.VoteCount),0) as TotalVotesReceived,
        max(u.Reputation) as Reputation,
        max(u.CreationDate) as UserCreationDate,
        max(u.LastAccessDate) as LastAccess,
        min(b.Date) filter (where b.Class = 1) as FirstGoldBadgeDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1,2)
    left join Comments c on c.UserId = u.Id
    left join (
      select PostId, count(*) as VoteCount
      from Votes
      where VoteTypeId in (1,2)
      group by PostId
    ) v on v.PostId = p.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostTagExplode as (
    select
        p.Id as PostId,
        trim(tag) as Tag
    from Posts p
    cross join lateral unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as tag
    where p.PostTypeId = 1 and p.Tags is not null
),
PostScoreRank as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate asc) as ScoreRank
    from Posts p
    where p.PostTypeId = 1
),
TopPostsByUser as (
    select 
        psr.OwnerUserId,
        psr.Id as PostId,
        psr.Title,
        psr.Score,
        psr.ViewCount,
        psr.CreationDate,
        count(distinct c.Id) filter (where c.CreationDate > psr.CreationDate) as CommentsAfterPost
    from PostScoreRank psr
    left join Comments c on c.PostId = psr.Id
    where psr.ScoreRank <= 3
    group by psr.OwnerUserId, psr.Id, psr.Title, psr.Score, psr.ViewCount, psr.CreationDate
),
DuplicatesWithLink as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as OriginalTitle,
        p2.Title as DuplicateTitle,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where pl.LinkTypeId = 3
),
PostCloseReasonsCount as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) 
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.PostId, crt.Name
),
UserBadgesRank as (
    select 
        b.UserId,
        b.Name,
        b.Class,
        row_number() over(partition by b.UserId order by b.Date asc) as BadgeRank,
        b.Date
    from Badges b
    where b.Class in (1,2,3)
),
UserBadgeSummary as (
    select
        ub.UserId,
        count(*) filter (where ub.Class = 1) as GoldBadges,
        count(*) filter (where ub.Class = 2) as SilverBadges,
        count(*) filter (where ub.Class = 3) as BronzeBadges,
        min(ub.Date) as FirstBadgeDate
    from UserBadgesRank ub
    group by ub.UserId
),
FinalResults as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.TotalVotesReceived,
        ua.UserCreationDate,
        ua.LastAccess,
        ua.FirstGoldBadgeDate,
        coalesce(ub.GoldBadges,0) as GoldBadgeCount,
        coalesce(ub.SilverBadges,0) as SilverBadgeCount,
        coalesce(ub.BronzeBadges,0) as BronzeBadgeCount,
        count(distinct dwl.PostId) as DuplicateQuestions,
        max(psc.CloseCount) as MaxCloseVotes,
        max(ta.ViewCount) as MaxViewCount,
        (select string_agg(distinct Tag, ', ') from PostTagExplode pte where pte.PostId in 
          (select psr.Id from Posts psr where psr.OwnerUserId = ua.UserId and psr.PostTypeId = 1)
        ) as DistinctTagsUsed,
        (select count(*) from TopPostsByUser tpu where tpu.OwnerUserId = ua.UserId and tpu.CommentsAfterPost > 0) as TopPostsWithCommentsAfter,
        (select avg(Score) from Posts where OwnerUserId = ua.UserId and PostTypeId = 1) as AvgQuestionScore
    from UserActivity ua
    left join DuplicatesWithLink dwl on dwl.PostId in
      (select Id from Posts where OwnerUserId = ua.UserId and PostTypeId = 1)
    left join PostCloseReasonsCount psc on psc.PostId in
      (select Id from Posts where OwnerUserId = ua.UserId and PostTypeId = 1)
    left join Posts ta on ta.OwnerUserId = ua.UserId and ta.PostTypeId = 1
    left join UserBadgeSummary ub on ub.UserId = ua.UserId
    group by ua.UserId, ua.DisplayName, ua.Reputation, ua.QuestionsAsked, ua.AnswersGiven, ua.CommentsMade, ua.TotalVotesReceived, ua.UserCreationDate, ua.LastAccess, ua.FirstGoldBadgeDate, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
)
select
    fr.UserId,
    fr.DisplayName,
    fr.Reputation,
    fr.QuestionsAsked,
    fr.AnswersGiven,
    fr.CommentsMade,
    fr.TotalVotesReceived,
    fr.DuplicateQuestions,
    coalesce(fr.MaxCloseVotes,0) as MaxCloseVotes,
    coalesce(fr.MaxViewCount,0) as MaxViewCount,
    fr.DistinctTagsUsed,
    fr.TopPostsWithCommentsAfter,
    fr.AvgQuestionScore,
    fr.GoldBadgeCount,
    fr.SilverBadgeCount,
    fr.BronzeBadgeCount,
    fr.UserCreationDate,
    fr.LastAccess,
    fr.FirstGoldBadgeDate,
    case
      when fr.Reputation > 10000 then 'Expert'
      when fr.Reputation between 5000 and 10000 then 'Advanced'
      when fr.Reputation between 1000 and 4999 then 'Intermediate'
      else 'Beginner'
    end as UserLevel,
    length(coalesce(fr.DistinctTagsUsed,'')) - length(replace(coalesce(fr.DistinctTagsUsed,''), ',', '')) + 1 as TagCount
from FinalResults fr
where fr.QuestionsAsked > 5
  and fr.AvgQuestionScore is not null
order by fr.Reputation desc, fr.GoldBadgeCount desc, fr.TopPostsWithCommentsAfter desc
limit 50;