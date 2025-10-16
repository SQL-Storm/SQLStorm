-- {"query": "29.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1562} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> all(r.Path)
    where t2.IsRequired = 1 and t2.Count < r.Count
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationRanks as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc) as ReputationRank,
        dense_rank() over (partition by u.Location order by u.Reputation desc) as LocationReputationRank
    from Users u
    where u.Reputation is not null
),
PostScoreStats as (
    select
        p.OwnerUserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionCount,
        count(*) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreationDate,
        a.Score as AnswerScore,
        u.DisplayName as AnswerOwner,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as CloserUserId,
        u.DisplayName as CloserUserName
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) 
    left join Users u on u.Id = ph.UserId
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as TotalUpVotes,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as TotalDownVotes,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        max(v.CreationDate) as LastVoteDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
    coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
    coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
    prs.QuestionCount,
    prs.AnswerCount,
    prs.AvgQuestionScore,
    prs.AvgAnswerScore,
    prs.MaxQuestionScore,
    prs.MaxAnswerScore,
    uas.TotalPosts,
    uas.TotalComments,
    uas.TotalUpVotes,
    uas.TotalDownVotes,
    uas.LastPostDate,
    uas.LastCommentDate,
    uas.LastVoteDate,
    u.CreationDate,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    ur.ReputationRank,
    ur.LocationReputationRank,
    cq.CloseReason,
    cq.CloseDate,
    cq.CloserUserName,
    tq.QuestionId,
    tq.Title as TopQuestionTitle,
    tq.QuestionCreationDate,
    tq.QuestionScore,
    tq.AnswerId,
    tq.AnswerCreationDate,
    tq.AnswerScore,
    tq.AnswerOwner
from Users u
left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
left join PostScoreStats prs on prs.OwnerUserId = u.Id
left join UserActivitySummary uas on uas.UserId = u.Id
left join UserReputationRanks ur on ur.Id = u.Id
left join LATERAL (
    select cq1.CloseReason, cq1.CloseDate, cq1.CloserUserName
    from ClosedQuestionsWithReasons cq1
    join Posts p1 on p1.Id = cq1.PostId
    where p1.OwnerUserId = u.Id
    order by cq1.CloseDate desc
    limit 1
) cq on true
left join LATERAL (
    select tq1.*
    from TopQuestionsWithAnswers tq1
    where tq1.AnswerRank = 1 and exists (
        select 1 from Posts p2 where p2.Id = tq1.QuestionId and p2.OwnerUserId = u.Id
    )
    order by tq1.QuestionScore desc
    limit 1
) tq on true
where u.Reputation > 1000
  and (u.Location is not null and u.Location <> '')
  and (u.AboutMe is not null and length(u.AboutMe) > 50)
  and exists (
    select 1 from Posts p where p.OwnerUserId = u.Id and p.Score > 10
  )
order by ur.ReputationRank
limit 100;