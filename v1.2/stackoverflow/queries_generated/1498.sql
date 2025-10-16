-- {"query": "1498.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1644} 
with RankedPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.ClosedDate,
        p.FavoriteCount,
        u.Reputation as OwnerReputation,
        u.Location as OwnerLocation,
        u.CreationDate as OwnerCreationDate,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByScoreView,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as UserRecentPostRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2) -- questions and answers
), BadgeCounts as (
    select 
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges
    group by UserId
), DupLinks as (
    select 
        pl.PostId, 
        count(pl.Id) filter (where lt.Name = 'Duplicate') as DupCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
), UserActivitySummary as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(com.Id) as CommentCount,
        coalesce(b.GoldBadges,0) as GoldBadgeCount,
        coalesce(b.SilverBadges,0) as SilverBadgeCount,
        coalesce(b.BronzeBadges,0) as BronzeBadgeCount,
        (select count(*) 
         from Votes v2 
         join Posts p2 on v2.PostId = p2.Id 
         where p2.OwnerUserId = u.Id and v2.VoteTypeId = 2) as UpVotesReceived,
        (select count(*) 
         from Votes v3 
         join Posts p3 on v3.PostId = p3.Id 
         where p3.OwnerUserId = u.Id and v3.VoteTypeId = 3) as DownVotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments com on com.UserId = u.Id
    left join BadgeCounts b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, b.GoldBadges, b.SilverBadges, b.BronzeBadges
), QuestionsWithLatestClosure as (
    select ph.PostId,
           max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as LastClosedAt,
           max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as LastReopenedAt,
           max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) end) as LastCloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId in (10, 11)
    group by ph.PostId
), QuestionsWithDuplicates as (
    select p.Id,
           coalesce(dl.DupCount,0) as DuplicateLinks,
           w.LastClosedAt,
           w.LastReopenedAt,
           w.LastCloseReasonId
    from Posts p
    left join DupLinks dl on p.Id = dl.PostId
    left join QuestionsWithLatestClosure w on p.Id = w.PostId
    where p.PostTypeId = 1
), QuestionStats as (
    select 
        q.Id,
        q.Title,
        q.Score, 
        q.ViewCount, 
        q.AnswerCount, 
        q.FavoriteCount,
        q.Tags,
        q.DuplicateLinks,
        q.LastClosedAt,
        q.LastReopenedAt,
        q.LastCloseReasonId,
        ATS.GoldBadges,
        ATS.SilverBadges,
        ATS.BronzeBadges,
        ATS.OwnerReputation,
        case 
            when q.LastClosedAt is null then 'Open' 
            when q.LastReopenedAt is not null and q.LastReopenedAt > q.LastClosedAt then 'Reopened'
            else 'Closed'
        end as CurrentStatus,
        regexp_replace(coalesce(q.Tags, ''), '[<>]', '', 'g') as CleanTags
    from 
    (
        select p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.Tags, p.OwnerUserId 
        from Posts p
        where p.PostTypeId = 1
    ) q
    left join BadgeCounts ATS on Q.OwnerUserId = ATS.UserId
    left join QuestionsWithDuplicates qd on q.Id = qd.Id
    left join QuestionsWithDuplicates q on q.Id = q.Id -- expanded for later filters
)
select 
    qs.Id as QuestionId,
    qs.Title,
    qs.Score,
    qs.ViewCount,
    qs.AnswerCount,
    qs.FavoriteCount,
    qs.DuplicateLinks,
    coalesce(qs.LastClosedAt, timestamp '1970-01-01') as LastClosedTimestamp,
    qs.LastReopenedAt,
    qs.LastCloseReasonId,
    qs.CurrentStatus,
    qs.GoldBadges,
    qs.SilverBadges,
    qs.BronzeBadges,
    coalesce(qs.OwnerReputation, 0) as OwnerReputation,
    qs.CleanTags,
    (case 
       when qs.AnswerCount > 0 then 
         round( cast(qs.Score as numeric) / qs.AnswerCount :: numeric, 2)
       else null
    end) as ScorePerAnswer,
    (case
       when qs.ViewCount > 0 then round(qs.FavoriteCount * 100.0 / qs.ViewCount, 2)
       else null
    end) as FavoriteRatioByViews,
    robrtc.Block_UserCount_Last7Days,
    us.QuestionCount,
    us.AnswerCount as UserAnswerCount,
    us.CommentCount as UserCommentCount,
    us.GoldBadgeCount as UserGoldBadges,
    sum(case when vh.VoteTypeId = 2 then 1 else 0 end) over (partition by qs.Id) as TotalUpvotes,
    sum(case when vh.VoteTypeId = 3 then 1 else 0 end) over (partition by qs.Id) as TotalDownvotes
from QuestionStats qs
left join UserActivitySummary us on qs.OwnerUserId = us.Id
left join Votes vh on vh.PostId = qs.Id and vh.VoteTypeId in (2, 3)
left join LATERAL (
    select count(distinct v.UserId) as Block_UserCount_Last7Days
    from Votes v 
    where v.PostId = qs.Id 
      and v.CreationDate >= now() - interval '7 days' 
      and v.VoteTypeId in (2, 3) 
) robrtc on true
where qs.Score > 10 
  and (qs.CurrentStatus = 'Open' or
      (qs.CurrentStatus = 'Closed' and qs.LastClosedAt < now() - interval '30 days'))
order by qs.Score desc, qs.ViewCount desc
limit 50;