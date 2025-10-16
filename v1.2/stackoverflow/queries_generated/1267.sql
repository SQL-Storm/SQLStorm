-- {"query": "1267.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1189} 
with UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
PostActivityRanks as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.OwnerDisplayName,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc nulls last) as RankWithinPostType,
        count(*) over (partition by p.PostTypeId) as PostTypeCount
    from Posts p
    where p.PostTypeId in (1,2)
),
AnswerStats as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score as AnswerScore,
        (select count(1) from Comments c where c.PostId = a.Id) as CommentCount,
        a.CreationDate,
        lag(a.Score) over (partition by a.ParentId order by a.CreationDate) as PreviousAnswerScore,
        lead(a.Score) over (partition by a.ParentId order by a.CreationDate) as NextAnswerScore
    from Posts a
    where a.PostTypeId = 2
),
QuestionsWithCloseReason as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) else null end) as CloseReasonId,
        max(crit.Name) as CloseReasonName
    from PostHistory ph
    left join CloseReasonTypes crit on crit.Id = cast(ph.Comment as int) and ph.PostHistoryTypeId = 10
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
HighScoringQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount,
        coalesce(q.AnswerCount, 0) as AnswerCount,
        UBC.TotalBadges,
        UBC.GoldBadges,
        UBC.SilverBadges,
        UBC.BronzeBadges,
        qc.CloseReasonName,
        row_number() over (order by q.Score desc nulls last, q.ViewCount desc nulls last) as ScoreRank
    from Posts q
    left join UserBadgeCounts UBC on q.OwnerUserId = UBC.UserId
    left join QuestionsWithCloseReason qc on q.Id = qc.PostId
    where q.PostTypeId = 1 and q.Score > 50
)
select 
    h.QuestionId,
    h.Title,
    h.QuestionScore,
    h.ViewCount,
    h.AnswerCount,
    h.TotalBadges,
    h.GoldBadges,
    h.SilverBadges,
    h.BronzeBadges,
    coalesce(h.CloseReasonName, 'Open') as CloseReason,
    a.AnswerId,
    a.AnswerScore,
    a.CommentCount,
    a.PreviousAnswerScore,
    a.NextAnswerScore,
    -- A calculated string showing the answer quality and comment density:
    concat(
        case 
            when a.AnswerScore >= h.QuestionScore * 0.8 then 'High Quality'
            when a.AnswerScore >= h.QuestionScore * 0.5 then 'Medium Quality'
            else 'Low Quality' end,
        ' - ',
        case 
            when a.CommentCount > 5 then 'High Engagement'
            when a.CommentCount between 2 and 5 then 'Moderate Engagement'
            else 'Low Engagement' end
    ) as AnswerAnalysis,
    -- A null-containing expression with string manipulation and boolean logic:
    case 
        when h.CloseReasonName is null and (h.ViewCount > 10000 or h.AnswerCount > 5) then concat('Popular & Active ', lower(h.Title))
        when h.CloseReasonName is not null then concat('Closed Reason: ', h.CloseReasonName)
        else 'Normal Post'
    end as PostSummary
from HighScoringQuestionsWithAnswers h
left join AnswerStats a on a.QuestionId = h.QuestionId
where (a.AnswerScore is null or a.AnswerScore > 5) 
union
select 
    b.Id as QuestionId,
    b.Title,
    b.Score as QuestionScore,
    b.ViewCount,
    coalesce(b.AnswerCount,0) as AnswerCount,
    0 as TotalBadges,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    'Open' as CloseReason,
    null as AnswerId,
    null as AnswerScore,
    null as CommentCount,
    null as PreviousAnswerScore,
    null as NextAnswerScore,
    'No answers passing filter' as AnswerAnalysis,
    'Ignore' as PostSummary
from Posts b
where b.PostTypeId = 1 and b.Score > 75 and b.Id not in (
    select distinct QuestionId from AnswerStats where AnswerScore > 5
)
order by QuestionScore desc, AnswerScore desc nulls last, ViewCount desc;