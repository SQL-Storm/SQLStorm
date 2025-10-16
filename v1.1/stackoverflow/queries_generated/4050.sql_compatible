with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.CommentCount, 0) as CommentCount,
        coalesce(p.ViewCount, 0) as ViewCount
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    where t.TagName is not null
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation
),
TopQuestionsWithDetails as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        (select count(*) from Comments c2 where c2.PostId = p.Id) as CommentCount,
        (select count(*) from Votes v2 where v2.PostId = p.Id and v2.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v3 where v3.PostId = p.Id and v3.VoteTypeId = 3) as DownVotes,
        case 
          when p.ClosedDate is not null then 'Closed'
          else 'Open'
        end as PostStatus,
        (p.Score * 4 + p.ViewCount / 10 + p.AnswerCount * 5 + 
         (select count(*) from Comments c3 where c3.PostId = p.Id) * 3 +
         (select count(*) from Votes v4 where v4.PostId = p.Id and v4.VoteTypeId = 2) * 6 -
         (select count(*) from Votes v5 where v5.PostId = p.Id and v5.VoteTypeId = 3) * 10 ) as EngagementScore
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
ClosedReasonSummary as (
    select 
        cht.Name as CloseReasonName,
        count(ph.Id) as CloseCount
    from PostHistory ph
    join PostHistoryTypes chtt on ph.PostHistoryTypeId = chtt.Id
    join CloseReasonTypes cht on cast(ph.Comment as integer) = cht.Id
    where ph.PostHistoryTypeId = 10
    group by cht.Name
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
)
select distinct
    tq.Id as QuestionId,
    tq.Title,
    tq.OwnerUserId,
    coalesce(tq.OwnerDisplayName, 'Unknown') as OwnerDisplayName,
    coalesce(ua.QuestionsAsked, 0) as UserQuestionsAsked,
    coalesce(ua.AnswersGiven, 0) as UserAnswersGiven,
    coalesce(ua.CommentsMade, 0) as UserCommentsMade,
    coalesce(ua.UpVotesReceived, 0) as UserUpVotesReceived,
    coalesce(ua.DownVotesReceived, 0) as UserDownVotesReceived,
    coalesce(ub.GoldBadges, 0) as UserGoldBadges,
    coalesce(ub.SilverBadges, 0) as UserSilverBadges,
    coalesce(ub.BronzeBadges, 0) as UserBronzeBadges,
    tq.Score,
    tq.ViewCount,
    tq.AnswerCount,
    tq.CommentCount,
    tq.UpVotes,
    tq.DownVotes,
    tq.PostStatus,
    tq.EngagementScore,
    rank() over (order by tq.EngagementScore desc) as QuestionEngagementRank,
    (
        select string_agg(t.TagName, ', ') 
        from Tags t 
        join Posts p2 on p2.Tags like concat('%<', t.TagName, '>%') 
        where p2.Id = tq.Id
    ) as TagsList,
    (
        select c.Text
        from Comments c
        where c.PostId = tq.Id
        order by c.CreationDate desc
        limit 1
    ) as LatestCommentText,
    coalesce(
        (
          select count(distinct pl.RelatedPostId)
          from PostLinks pl
          where pl.PostId = tq.Id and pl.LinkTypeId = 3
        ), 0) as DuplicateCount
from TopQuestionsWithDetails tq
left join UserActivity ua on ua.UserId = tq.OwnerUserId
left join UserBadgeCounts ub on ub.UserId = tq.OwnerUserId
where tq.EngagementScore > (
    select avg(EngagementScore) from TopQuestionsWithDetails
)
group by
    tq.Id,
    tq.Title,
    tq.OwnerUserId,
    tq.OwnerDisplayName,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.CommentsMade,
    ua.UpVotesReceived,
    ua.DownVotesReceived,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    tq.Score,
    tq.ViewCount,
    tq.AnswerCount,
    tq.CommentCount,
    tq.UpVotes,
    tq.DownVotes,
    tq.PostStatus,
    tq.EngagementScore
order by QuestionEngagementRank
limit 50;