-- {"query": "138.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1575} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id and not t.TagName = any(r.Path)
    where t.IsModeratorOnly = 0 and t.IsRequired = 0 and r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) over (partition by u.Id order by u.CreationDate rows between unbounded preceding and current row) as UpVotesWindow,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) over (partition by u.Id order by u.CreationDate rows between unbounded preceding and current row) as DownVotesWindow
    from Users u
    left join Votes v on v.UserId = u.Id and v.CreationDate >= u.CreationDate
),
PostScoreStats as (
    select
        p.OwnerUserId,
        p.PostTypeId,
        count(*) as PostCount,
        avg(p.Score) as AvgScore,
        max(p.Score) as MaxScore,
        min(p.Score) as MinScore,
        sum(case when p.Score > 0 then 1 else 0 end) as PositiveScoreCount,
        sum(case when p.Score <= 0 then 1 else 0 end) as NonPositiveScoreCount
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId > 0
    group by p.OwnerUserId, p.PostTypeId
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.Score > 10 and q.ViewCount > 1000
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as CloserUserId,
        u.DisplayName as CloserUserName
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostId in (select Id from Posts where PostTypeId = 1)
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        count(distinct v.Id) as TotalVotes,
        count(distinct b.Id) as TotalBadges,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        max(v.CreationDate) as LastVoteDate,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
    coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
    coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
    pas.PostCount as TotalAnswers,
    pas.AvgScore as AvgAnswerScore,
    pas.MaxScore as MaxAnswerScore,
    pas.PositiveScoreCount as PositiveAnswerCount,
    pqs.QuestionId,
    pqs.Title as TopQuestionTitle,
    pqs.QuestionScore,
    pqs.ViewCount as QuestionViews,
    pqs.AnswerId,
    pqs.AnswerScore,
    pqs.AnswerOwnerName,
    cq.CloseDate,
    cq.CloseReason,
    cq.CloserUserName,
    uas.TotalPosts,
    uas.TotalComments,
    uas.TotalVotes,
    uas.TotalBadges,
    uas.LastPostDate,
    uas.LastCommentDate,
    uas.LastVoteDate,
    uas.LastBadgeDate,
    rth.Level as TagHierarchyLevel,
    array_to_string(rth.Path, ' > ') as TagPath
from Users u
left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
left join PostScoreStats pas on pas.OwnerUserId = u.Id and pas.PostTypeId = 2
left join (
    select distinct on (q.Id) q.Id, q.Title, q.Score as QuestionScore, q.ViewCount, a.Id as AnswerId, a.Score as AnswerScore, u.DisplayName as AnswerOwnerName
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
    order by q.Id, a.Score desc nulls last, a.CreationDate asc nulls last
) pqs on pqs.AnswerOwnerName = u.DisplayName
left join ClosedQuestionsWithReasons cq on cq.PostId = pqs.QuestionId
left join UserActivitySummary uas on uas.UserId = u.Id
left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(coalesce((select Tags from Posts where OwnerUserId = u.Id and PostTypeId = 1 order by Score desc limit 1),''), '><'))
where u.Reputation > 1000
order by u.Reputation desc, pqs.QuestionScore desc
limit 100;