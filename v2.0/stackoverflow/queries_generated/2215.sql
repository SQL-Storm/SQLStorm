-- {"query": "2215.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1702} 
with RecursiveTagStats as (
    select 
        t.Id as TagId,
        t.TagName,
        t.Count,
        p.OwnerUserId,
        u.DisplayName,
        row_number() over (partition by t.Id order by p.Score desc nulls last, p.CreationDate) as rn,
        count(*) over (partition by t.Id) as TagPostCount,
        sum(coalesce(p.Score,0)) over (partition by t.Id) as TagScoreSum
    from 
        Tags t
        left join Posts p on p.PostTypeId = 1 and position(concat('<', t.TagName, '>') in coalesce(p.Tags, '')) > 0
        left join Users u on p.OwnerUserId = u.Id
    where 
        t.IsModeratorOnly = 0 and t.IsRequired = 0
), TopPostersPerTag as (
    select 
        TagId, TagName, OwnerUserId, DisplayName, rn
    from RecursiveTagStats
    where rn <= 3
), PostBadgesAgg as (
    select 
        b.UserId,
        string_agg(distinct b.Name || ' (' || b.Class || ')', ', ' order by b.Class, b.Name) as Badges,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges
    from Badges b
    group by b.UserId
), PostAnswerWindow as (
    select 
        p.Id, p.ParentId, p.Score, p.CreationDate, p.OwnerUserId,
        row_number() over (partition by p.ParentId order by p.Score desc nulls last, p.CreationDate) as AnswerRank
    from Posts p
    where p.PostTypeId = 2
), CteQuestionsWithAcceptedAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        q.CreationDate as QuestionDate,
        aa.Id as AcceptedAnswerId,
        aa.Score as AcceptedAnswerScore,
        aa.OwnerUserId as AcceptedAnswerOwner,
        coalesce(ba.Badges,'') as AcceptedAnswerBadges
    from 
        Posts q
        left join Posts aa on aa.Id = q.AcceptedAnswerId
        left join PostBadgesAgg ba on ba.UserId = aa.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
), CloseVoteCounts as (
    select 
        ph.PostId,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseVotesCount,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as LastCloseVoteDate,
        max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) else null end) over (partition by ph.PostId) as CloseReasonId
    from 
        PostHistory ph
    group by ph.PostId
), ComplexFilteredQuestions as (
    select 
        q.Id, q.Title, q.Score, q.ViewCount, q.Tags, q.CreationDate, q.OwnerUserId,
        coalesce(cvc.CloseVotesCount,0) as CloseVotesCount,
        cvc.LastCloseVoteDate,
        cr.Name as CloseReasonName
    from 
        Posts q
        left join CloseVoteCounts cvc on cvc.PostId = q.Id
        left join CloseReasonTypes cr on cr.Id = coalesce((select max(ph.Comment::int) from PostHistory ph where ph.PostId = q.Id and ph.PostHistoryTypeId = 10), null)
    where 
        q.PostTypeId = 1
        and (q.Score > 5 or q.ViewCount > 1000 or coalesce(cvc.CloseVotesCount,0) > 0)
), UnionedPostJoin as (
    select 
        q.Id as QuestionId,
        a.Id as AnswerId,
        u.DisplayName as QuestionOwnerName,
        ua.DisplayName as AnswerOwnerName,
        q.Score as QuestionScore,
        a.Score as AnswerScore,
        q.Tags,
        pb.Badges as AnswerOwnerBadges,
        row_number() over (partition by q.Id order by a.Score desc nulls last) as AnswerOrd
    from 
        Posts q
        left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
        left join Users u on u.Id = q.OwnerUserId
        left join Users ua on ua.Id = a.OwnerUserId
        left join PostBadgesAgg pb on pb.UserId = a.OwnerUserId
    where q.PostTypeId = 1
), CorrelatedSubQueryTopComment as (
    select 
        p.Id as PostId,
        (select c.Text from Comments c where c.PostId = p.Id order by c.Score desc nulls last limit 1) as TopCommentText,
        (select c.UserDisplayName from Comments c where c.PostId = p.Id order by c.Score desc nulls last limit 1) as TopCommentUser,
        (select c.Score from Comments c where c.PostId = p.Id order by c.Score desc nulls last limit 1) as TopCommentScore
    from Posts p
    where p.PostTypeId in (1,2)
), WindowFunctionRanks as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        dense_rank() over (order by p.Score desc nulls last) as ScoreRank,
        ntile(5) over (order by p.ViewCount desc nulls last) as ViewCountTile,
        lag(p.Score) over (order by p.Score desc nulls last) as PrevScore,
        lead(p.Score) over (order by p.Score desc nulls last) as NextScore
    from Posts p
    where p.PostTypeId = 1
)
select
    q.Id as QuestionId,
    q.Title,
    q.Score,
    q.ViewCount,
    q.Tags,
    q.CreationDate,
    u.DisplayName as QuestionOwner,
    pb.Badges as QuestionOwnerBadges,
    cvc.CloseVotesCount,
    cvc.LastCloseVoteDate,
    cr.Name as CloseReasonName,
    coalesce(cca.AcceptedAnswerScore,0) as AcceptedAnswerScore,
    cca.AcceptedAnswerBadges,
    ts.TopPosters,
    tc.TopCommentText,
    tc.TopCommentUser,
    tc.TopCommentScore,
    wfr.ScoreRank,
    wfr.ViewCountTile,
    wfr.PrevScore,
    wfr.NextScore
from 
    ComplexFilteredQuestions q
    left join Users u on u.Id = q.OwnerUserId
    left join PostBadgesAgg pb on pb.UserId = q.OwnerUserId
    left join CloseVoteCounts cvc on cvc.PostId = q.Id
    left join CloseReasonTypes cr on cr.Id = coalesce((select max(ph.Comment::int) from PostHistory ph where ph.PostId = q.Id and ph.PostHistoryTypeId = 10), null)
    left join CteQuestionsWithAcceptedAnswers cca on cca.QuestionId = q.Id
    left join (
        select 
            TagId,
            TagName,
            string_agg(DisplayName, ', ' order by rn) as TopPosters
        from TopPostersPerTag
        group by TagId, TagName
    ) ts on position(concat('<', ts.TagName, '>') in coalesce(q.Tags, '')) > 0
    left join CorrelatedSubQueryTopComment tc on tc.PostId = q.Id
    left join WindowFunctionRanks wfr on wfr.Id = q.Id
where 
    (q.ViewCount > 500 or q.Score > 10 or cvc.CloseVotesCount > 0)
order by q.ViewCount desc nulls last, q.Score desc nulls last
limit 100;