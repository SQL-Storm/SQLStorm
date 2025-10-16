-- {"query": "392.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1665} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews,
        coalesce(p.Score, 0) as TotalScore
    from Tags t
    left join (
        select
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as TagName,
            sum(case when p.PostTypeId = 1 then p.AnswerCount else 0 end) as AnswerCount,
            sum(case when p.PostTypeId = 1 then p.ViewCount else 0 end) as ViewCount,
            sum(case when p.PostTypeId = 1 then p.Score else 0 end) as Score
        from Posts p
        where p.Tags is not null
        group by 1
    ) p on p.TagName = t.TagName
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    where p.OwnerUserId is not null
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        p.Title,
        p.OwnerUserId
    from PostHistory ph
    inner join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    inner join Posts p on p.Id = ph.PostId
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
UserCloseStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct c.PostId) as ClosedQuestionsCount,
        count(distinct case when c.CloseReason = 'Duplicate' then c.PostId end) as DuplicateClosedCount,
        count(distinct case when c.CloseReason = 'Off-topic' then c.PostId end) as OffTopicClosedCount
    from Users u
    left join ClosedQuestionsWithReasons c on c.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
AnswerScores as (
    select
        a.Id,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
TopAnswersWithQuestion as (
    select
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwner,
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        a.Score as AnswerScore,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        u.DisplayName as AnswerOwnerName,
        u2.DisplayName as QuestionOwnerName
    from AnswerScores a
    inner join Posts q on q.Id = a.QuestionId and q.PostTypeId = 1
    left join Users u on u.Id = a.OwnerUserId
    left join Users u2 on u2.Id = q.OwnerUserId
    where a.AnswerRank = 1
),
UserVoteSummary as (
    select
        v.UserId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotesCast,
        count(*) filter (where vt.Name = 'DownMod') as DownVotesCast,
        count(*) filter (where vt.Name = 'Favorite') as FavoritesCast,
        count(*) filter (where vt.Name = 'Close') as CloseVotesCast
    from Votes v
    inner join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        coalesce(pq.QuestionCount, 0) as QuestionCount,
        coalesce(pa.AnswerCount, 0) as AnswerCount,
        coalesce(cmt.CommentCount, 0) as CommentCount,
        coalesce(vs.UpVotesCast, 0) as UpVotesCast,
        coalesce(vs.DownVotesCast, 0) as DownVotesCast,
        coalesce(vs.FavoritesCast, 0) as FavoritesCast,
        coalesce(vs.CloseVotesCast, 0) as CloseVotesCast
    from Users u
    left join (
        select OwnerUserId, count(*) as QuestionCount
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) pq on pq.OwnerUserId = u.Id
    left join (
        select OwnerUserId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) pa on pa.OwnerUserId = u.Id
    left join (
        select UserId, count(*) as CommentCount
        from Comments
        group by UserId
    ) cmt on cmt.UserId = u.Id
    left join UserVoteSummary vs on vs.UserId = u.Id
)
select
    t.Id as TagId,
    t.TagName,
    t.Count as TagTotalCount,
    t.TotalAnswers,
    t.TotalViews,
    t.TotalScore,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TagBasedBadges,
    ucs.ClosedQuestionsCount,
    ucs.DuplicateClosedCount,
    ucs.OffTopicClosedCount,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.CommentCount,
    uas.UpVotesCast,
    uas.DownVotesCast,
    uas.FavoritesCast,
    uas.CloseVotesCast,
    ta.AnswerId,
    ta.AnswerOwnerName,
    ta.QuestionTitle,
    ta.AnswerScore,
    ta.QuestionScore,
    ta.QuestionViews,
    case
        when ta.AnswerScore > ta.QuestionScore then 'Answer better than question'
        when ta.AnswerScore = ta.QuestionScore then 'Answer equals question score'
        else 'Answer lower than question'
    end as AnswerVsQuestionScoreComparison
from RecursiveTagCounts t
left join Users u on u.Id = (select OwnerUserId from Posts p where p.Tags like '%' || t.TagName || '%' limit 1)
left join UserBadgeStats ubs on ubs.UserId = u.Id
left join UserCloseStats ucs on ucs.UserId = u.Id
left join UserActivitySummary uas on uas.Id = u.Id
left join TopAnswersWithQuestion ta on ta.AnswerOwner = u.Id and ta.QuestionTitle ilike '%' || t.TagName || '%'
where t.Count > 1000
order by t.TotalScore desc, ubs.GoldBadges desc, uas.QuestionCount desc
limit 100;