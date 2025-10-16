-- {"query": "896.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1558} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(array_agg(p.Id) filter (where p.Id is not null), '{}') as PostIds
    from Tags t
    left join Posts p on p.Tags like '%' || t.TagName || '%'
    group by t.Id, t.TagName, t.Count
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        row_number() over (order by u.Reputation desc, u.CreationDate) as UserRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.OwnerUserId as QuestionOwnerId,
        count(a.Id) as TotalAnswers,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) filter (where a.Score >= 0) as AvgPositiveAnswerScore,
        bool_or(a.Score > 10) as HasHighlyScoredAnswer
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.OwnerUserId
),
PostVotesAgg as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteVotes,
        count(v.Id) as TotalVotes
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
RankedTopPosts as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        pa.TotalAnswers,
        pa.MaxAnswerScore,
        pa.AvgPositiveAnswerScore,
        p.CreationDate,
        u.DisplayName as OwnerName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC NULLS LAST) as RankByScore
    from Posts p
    left join PostAnswerStats pa on pa.QuestionId = p.Id
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1, 2)  -- questions and answers
),
LinkInfo as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p.Title as RelatedPostTitle,
        p.PostTypeId as RelatedPostType
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p on p.Id = pl.RelatedPostId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.CreationDate,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between 29 preceding and current row) as QuestionsLast30Days,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between 29 preceding and current row) as AnswersLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
TopUsersByActivity as (
    select
        UserId,
        DisplayName,
        max(QuestionsLast30Days) as MaxQuestions30d,
        max(AnswersLast30Days) as MaxAnswers30d
    from UserActivityWindow
    group by UserId, DisplayName
),
CorrelatedCloseReasons as (
    select distinct
        ph.PostId,
        crt.Name as CloseReasonName
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = ph.Comment::int
    where ph.PostHistoryTypeId = 10 and ph.Comment ~ '^\d+$'
),
AggregatedComments as (
    select
        c.PostId,
        string_agg(distinct c.UserDisplayName || ': ' || left(c.Text, 50), ' ||| ' order by c.CreationDate desc) as RecentCommentSnippets,
        count(c.Id) filter (where c.CreationDate > now() - interval '7 days') as CommentsLast7Days
    from Comments c
    group by c.PostId
)
select
    rtp.Id as PostId,
    rtp.Title,
    rtp.Score,
    rtp.ViewCount,
    rtp.Tags,
    rtp.TotalAnswers,
    rtp.MaxAnswerScore,
    rtp.AvgPositiveAnswerScore,
    rtp.CreationDate,
    rtp.OwnerName,
    linfo.LinkTypeName,
    linfo.RelatedPostId,
    linfo.RelatedPostTitle,
    linfo.RelatedPostType,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TagBasedBadges,
    ta.MaxQuestions30d,
    ta.MaxAnswers30d,
    cc.CloseReasonName,
    ac.RecentCommentSnippets,
    ac.CommentsLast7Days,
    case
        when rtp.Score > 100 and rtp.TotalAnswers > 10 and ubs.GoldBadges > 0 then 'HighImpact'
        when rtp.Score between 50 and 100 then 'MediumImpact'
        else 'LowImpact'
    end as ImpactCategory,
    case
        when position('sql' in lower(rtp.Tags)) > 0 then 'ContainsSQLTag'
        else 'NoSQLTag'
    end as TagSQLPresence,
    -- string expression with null logic and coalesce
    coalesce(rtp.Title, 'No Title') || ' [' || coalesce(lnfo.LinkTypeName, 'No Link') || ']' as TitleWithLinkType
from RankedTopPosts rtp
left join LinkInfo linfo on linfo.PostId = rtp.Id
left join UserBadgeStats ubs on ubs.UserId = (select OwnerUserId from Posts where Id = rtp.Id limit 1)
left join TopUsersByActivity ta on ta.UserId = ubs.UserId
left join CorrelatedCloseReasons cc on cc.PostId = rtp.Id
left join AggregatedComments ac on ac.PostId = rtp.Id
where rtp.RankByScore <= 100
order by rtp.Score desc, rtp.ViewCount desc nulls last;