-- {"query": "4014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1537} 
with RecursiveTagCounts as (
    select 
        t.Id,
        t.TagName,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.FavoriteCount, 0) as FavoriteCount,
        coalesce(u.Reputation, 0) as OwnerReputation,
        p.OwnerUserId,
        p.Id as PostId
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    left join Users u on u.Id = p.OwnerUserId
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select 
        rtc.Id,
        rtc.TagName,
        rtc.AnswerCount + coalesce(p.AnswerCount, 0),
        rtc.FavoriteCount + coalesce(p.FavoriteCount, 0),
        rtc.OwnerReputation,
        rtc.OwnerUserId,
        rtc.PostId
    from RecursiveTagCounts rtc
    join Posts p on p.ParentId = rtc.PostId and p.PostTypeId = 2
    where p.OwnerUserId is not null
), BadgeCounts as (
    select 
        b.UserId, 
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
), UserBadgesSummary as (
    select 
        u.Id as UserId, 
        coalesce(sum(case when bc.Class = 1 then bc.BadgeCount else 0 end),0) as GoldBadges,
        coalesce(sum(case when bc.Class = 2 then bc.BadgeCount else 0 end),0) as SilverBadges,
        coalesce(sum(case when bc.Class = 3 then bc.BadgeCount else 0 end),0) as BronzeBadges
    from Users u
    left join BadgeCounts bc on bc.UserId = u.Id
    group by u.Id
), PostVoteStats as (
    select 
        p.Id as PostId,
        p.OwnerUserId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteVotes
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.OwnerUserId
), CloseReasonsCount as (
    select 
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseVotes
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    left join CloseReasonTypes crt on crt.Id::int = NULLIF(ph.Comment, '')::int
    where ph.PostHistoryTypeId = 10 and crt.Name is not null
    group by ph.PostId, crt.Name
), UserActivityWindow as (
    select 
        u.Id,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        count(distinct ph.Id) as PostEditsCount,
        row_number() over (partition by u.Id order by p.CreationDate desc) as LatestPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id
), UserRecentPosts as (
    select 
        p.Id as PostId,
        p.Title,
        p.CreationDate,
        u.Id as UserId,
        row_number() over (partition by u.Id order by p.CreationDate desc) as PostRank
    from Posts p
    join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
), UserTopTags as (
    select distinct 
        u.Id as UserId,
        t.TagName,
        count(*) over (partition by u.Id, t.TagName) as TagFrequency
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.Tags is not null
    cross join lateral unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as t(TagName)
), CombinedStats as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Views,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        ua.QuestionsCount,
        ua.AnswersCount,
        ua.PostEditsCount,
        case when ua.QuestionsCount = 0 then null else (ubs.GoldBadges::float / ua.QuestionsCount) end as GoldBadgePerQuestionRatio,
        (select max(TagFrequency) from UserTopTags utt where utt.UserId = u.Id) as MaxTagFrequency,
        (select string_agg(distinct t.TagName, ',' order by count(*) desc) from UserTopTags t where t.UserId = u.Id limit 3) as Top3Tags
    from Users u
    left join UserBadgesSummary ubs on ubs.UserId = u.Id
    left join UserActivityWindow ua on ua.Id = u.Id
)
select 
    cs.Id as UserId,
    cs.DisplayName,
    cs.Reputation,
    cs.Views,
    cs.GoldBadges,
    cs.SilverBadges,
    cs.BronzeBadges,
    cs.QuestionsCount,
    cs.AnswersCount,
    cs.PostEditsCount,
    cs.GoldBadgePerQuestionRatio,
    cs.MaxTagFrequency,
    cs.Top3Tags,
    coalesce(
        (select count(distinct pl.PostId) 
         from PostLinks pl 
         where pl.PostId in (select Id from Posts where OwnerUserId = cs.Id)
           and exists (
                select 1 from Votes v where v.PostId = pl.RelatedPostId and v.VoteTypeId = 2
           )
        ),0) as LinkedPostsWithUpvotes,
    coalesce(
        (select count(*) 
         from Comments c 
         where c.UserId = cs.Id 
           and c.CreationDate > (select max(CreationDate) from Posts where OwnerUserId = cs.Id)
        ), 0) as CommentsAfterLastPost,
    (select string_agg(distinct ph.Comment, ',' order by ph.CreationDate desc) 
     from PostHistory ph 
     where ph.UserId = cs.Id and ph.PostHistoryTypeId in (10,11) limit 3) as LatestCloseReopenReasons
from CombinedStats cs
where cs.Reputation > 1000
  and cs.AnswersCount > 20
order by cs.GoldBadgePerQuestionRatio desc nulls last, cs.Reputation desc
limit 50;