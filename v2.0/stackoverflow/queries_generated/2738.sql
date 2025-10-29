-- {"query": "2738.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1194} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        array[t.Id] as Path,
        1 as Depth
    from Tags t
    where not t.IsModeratorOnly = 1

    union all

    select
        t.Id,
        t.TagName,
        r.Path || t.Id,
        r.Depth + 1
    from Tags t
    join RecursiveTagHierarchy r on t.ExcerptPostId = r.Id
    where t.Id != all(r.Path)
),
UserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class in (1,2,3)
),
TopUserBadges as (
    select UserId, BadgeName, Class
    from UserBadges
    where rn <= 5
),
PostVotesSummary as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
        count(case when v.VoteTypeId = 3 then 1 end) as DownVotes,
        count(case when v.VoteTypeId = 1 then 1 end) as AcceptedVotes,
        coalesce(sum(v.BountyAmount),0) as TotalBounty,
        max(v.CreationDate) as LastVoteDate
    from Posts p
    left join Votes v on p.Id = v.PostId
    group by p.Id, p.PostTypeId, p.OwnerUserId
),
PostWithAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) filter (where a.Score > 0) as AvgAnswerScorePositive,
        sum(case when a.Score > 10 then 1 else 0 end) as HighlyScoredAnswers,
        max(a.CreationDate) as LastAnswerDate
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate
),
QuestionsClosedReason as (
    select 
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as ClosedAt
    from PostHistory ph
    join CloseReasonTypes crt on try_cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null
),
QuestionsWithCloseFlag as (
    select q.Id, q.Title, qc.CloseReasonName, qc.ClosedAt
    from Posts q
    left join QuestionsClosedReason qc on q.Id = qc.PostId
    where q.PostTypeId = 1
),
RankedPosts as (
    select
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc nulls last) as rn
    from Posts p
    where p.PostTypeId in (1, 2)
),
UserPostStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersCount,
        sum(p.Score) as TotalScore,
        avg(p.Score) as AvgScore,
        max(p.Score) as MaxScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
TopContributors as (
    select *
    from UserPostStats
    where TotalPosts > 50
    order by TotalScore desc
    limit 100
)
select
    tc.UserId,
    tc.DisplayName,
    tc.TotalPosts,
    tc.QuestionsCount,
    tc.AnswersCount,
    tc.TotalScore,
    tc.AvgScore,
    tb.BadgeName,
    tb.Class as BadgeClass,
    pws.QuestionId,
    pws.Title as QuestionTitle,
    pws.AnswerCount,
    pvs.UpVotes,
    pvs.DownVotes,
    pvs.TotalBounty,
    qc.CloseReasonName,
    qc.ClosedAt,
    r.PostId as TopPostId,
    r.Score as TopPostScore,
    r.ViewCount as TopPostViews
from TopContributors tc
left join TopUserBadges tb on tb.UserId = tc.UserId
left join PostWithAnswers pws on pws.QuestionId in (
    select p.Id from Posts p where p.OwnerUserId = tc.UserId and p.PostTypeId = 1 limit 1
)
left join PostVotesSummary pvs on pvs.PostId = pws.QuestionId
left join QuestionsWithCloseFlag qc on qc.Id = pws.QuestionId
left join RankedPosts r on r.OwnerUserId = tc.UserId and r.rn = 1
where (tb.BadgeName is not null or tc.TotalPosts > 100)
order by tc.TotalScore desc, tc.TotalPosts desc
limit 500;