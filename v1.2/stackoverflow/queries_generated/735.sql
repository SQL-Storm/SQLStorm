-- {"query": "735.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1526} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.PostTypeId,
        u.Id as OwnerUserId,
        u.Reputation,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    left join Posts p on p.Tags like '%' || '<' || t.TagName || '>' || '%'
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 -- questions only
),
TopScoredQuestionsPerTag as (
    select
        Id,
        TagName,
        Count,
        PostId,
        Score,
        ViewCount,
        OwnerUserId,
        Reputation
    from RecursiveTagCounts
    where rn <= 5
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViewCount,
        count(a.Id) as AnswerCount,
        coalesce(avg(a.Score), 0) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        b.GoldBadges,
        b.SilverBadges,
        b.BronzeBadges
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Votes v on v.PostId = q.Id
    left join Users u on u.Id = q.OwnerUserId
    left join UserBadgeSummary b on b.UserId = u.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, u.DisplayName, u.Reputation, b.GoldBadges, b.SilverBadges, b.BronzeBadges
),
PostHistoryCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
RankedCloseReasons as (
    select
        phcr.PostId,
        phcr.CloseReasonName,
        phcr.CloseDate,
        row_number() over (partition by phcr.PostId order by phcr.CloseDate desc) as rn
    from PostHistoryCloseReasons phcr
),
LatestCloseReasons as (
    select
        PostId,
        CloseReasonName,
        CloseDate
    from RankedCloseReasons
    where rn = 1
),
QuestionCommentStats as (
    select
        p.Id as QuestionId,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ' order by c.CreationDate desc) as RecentCommenters
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id
),
FinalAggregatedData as (
    select
        qas.QuestionId,
        qas.Title,
        qas.QuestionCreation,
        qas.QuestionScore,
        qas.QuestionViewCount,
        qas.AnswerCount,
        qas.AvgAnswerScore,
        qas.MaxAnswerScore,
        qas.TotalUpVotes,
        qas.TotalDownVotes,
        qas.OwnerDisplayName,
        qas.OwnerReputation,
        qas.GoldBadges,
        qas.SilverBadges,
        qas.BronzeBadges,
        lcr.CloseReasonName,
        lcr.CloseDate,
        qcs.CommentCount,
        qcs.LastCommentDate,
        qcs.RecentCommenters,
        tsc.TagName,
        tsc.Count as TagPopularity,
        tsc.Score as TopQuestionScore,
        tsc.ViewCount as TopQuestionViewCount,
        tsc.Reputation as TopQuestionOwnerReputation
    from QuestionAnswerStats qas
    left join LatestCloseReasons lcr on lcr.PostId = qas.QuestionId
    left join QuestionCommentStats qcs on qcs.QuestionId = qas.QuestionId
    left join TopScoredQuestionsPerTag tsc on tsc.PostId = qas.QuestionId
    where qas.AnswerCount > 0
)
select
    fad.QuestionId,
    fad.Title,
    fad.QuestionCreation,
    fad.QuestionScore,
    fad.QuestionViewCount,
    fad.AnswerCount,
    fad.AvgAnswerScore,
    fad.MaxAnswerScore,
    fad.TotalUpVotes,
    fad.TotalDownVotes,
    coalesce(fad.OwnerDisplayName, 'Unknown') as OwnerDisplayName,
    fad.OwnerReputation,
    coalesce(fad.GoldBadges, 0) as GoldBadges,
    coalesce(fad.SilverBadges, 0) as SilverBadges,
    coalesce(fad.BronzeBadges, 0) as BronzeBadges,
    coalesce(fad.CloseReasonName, 'Open') as CloseReasonName,
    fad.CloseDate,
    fad.CommentCount,
    fad.LastCommentDate,
    fad.RecentCommenters,
    fad.TagName,
    fad.TagPopularity,
    fad.TopQuestionScore,
    fad.TopQuestionViewCount,
    fad.TopQuestionOwnerReputation,
    length(fad.Title) as TitleLength,
    case
        when fad.CloseReasonName is null then false
        else true
    end as IsClosed,
    (fad.QuestionScore * 1.0 / nullif(fad.AnswerCount,0))::numeric(10,2) as ScorePerAnswer,
    (fad.TotalUpVotes - fad.TotalDownVotes) as NetVotes,
    substring(fad.Title from '[A-Za-z]+') as FirstAlphaWordInTitle,
    case 
        when fad.CommentCount > 10 then 'Highly Commented'
        when fad.CommentCount between 5 and 10 then 'Moderately Commented'
        else 'Low Comments'
    end as CommentLevel
from FinalAggregatedData fad
where fad.QuestionCreation > current_date - interval '1 year'
order by fad.QuestionScore desc nulls last, fad.AnswerCount desc, fad.QuestionViewCount desc
limit 100;