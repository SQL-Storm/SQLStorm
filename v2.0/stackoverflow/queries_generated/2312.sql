-- {"query": "2312.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1355} 
with RecursiveTagCounts as (
    select 
        t.Id as TagId,
        t.TagName,
        p.Id as PostId,
        p.CreationDate,
        pn.ExcerptPostId,
        ROW_NUMBER() over (partition by t.Id order by p.CreationDate desc) as rn
    from 
        Tags t
    left join 
        Posts p on p.Tags like concat('%<', t.TagName, '>%')
    left join 
        Posts pn on pn.Id = t.ExcerptPostId
    where 
        p.PostTypeId = 1 or p.Id is null
),
UserBadgeAgg as (
    select 
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        max(b.Date) as LastBadgeDate,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedCount
    from 
        Badges b
    group by 
        b.UserId, b.Class
),
PostAnswerVotes as (
    select 
        p.Id as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        v.VoteTypeId,
        count(v.Id) filter (where v.VoteTypeId = 2) as AnswerUpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as AnswerDownVotes
    from 
        Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    left join Votes v on v.PostId = a.Id
    where 
        p.PostTypeId = 1
    group by 
        p.Id, a.Id, a.Score, v.VoteTypeId
),
UserActivityWindow as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativePosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeQuestions,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeAnswers
    from 
        Users u
    left join Posts p on p.OwnerUserId = u.Id
),
ClosedQuestionsWithReason as (
    select 
        ph.PostId,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        max(ph.CreationDate) as CloseDate
    from 
        PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where 
        ph.PostHistoryTypeId = 10
    group by 
        ph.PostId, ph.Comment, crt.Name
),
DuplicateLinks as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from 
        PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where 
        pl.LinkTypeId = 3
),
QuestionWithDuplicatesAndClose as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.ViewCount,
        p.Score,
        p.Tags,
        dq.RelatedPostId as DuplicateOf,
        ccwr.CloseReasonId,
        ccwr.CloseReasonName,
        ccwr.CloseDate,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        uba.BadgeCount as UserBadgeCount,
        uba.LastBadgeDate,
        uba.TagBasedCount
    from 
        Posts p
    left join DuplicateLinks dq on dq.PostId = p.Id
    left join ClosedQuestionsWithReason ccwr on ccwr.PostId = p.Id
    left join Users u on p.OwnerUserId = u.Id
    left join UserBadgeAgg uba on uba.UserId = u.Id and uba.Class = 1
    where 
        p.PostTypeId = 1
),
RankedQuestions as (
    select 
        q.*,
        dense_rank() over (partition by q.CloseReasonName order by q.ViewCount desc, q.Score desc) as RankWithinCloseReason,
        ntile(5) over (order by coalesce(q.OwnerReputation, 0) desc) as ReputationQuintile
    from 
        QuestionWithDuplicatesAndClose q
)
select 
    rq.QuestionId,
    rq.Title,
    rq.ViewCount,
    rq.Score,
    rq.Tags,
    rq.DuplicateOf,
    rq.CloseReasonName,
    rq.CloseDate,
    rq.OwnerDisplayName,
    rq.OwnerReputation,
    rq.UserBadgeCount,
    rq.LastBadgeDate,
    rq.TagBasedCount,
    rq.RankWithinCloseReason,
    rq.ReputationQuintile,
    -- Correlated subquery: get number of comments on the question with text length > 50 or null-safe logic
    (select count(*) from Comments c 
     where c.PostId = rq.QuestionId 
       and (length(c.Text) > 50 or c.Text is null)) as LongCommentCount,
    -- Complex string expression, extract first tag if exists
    coalesce(split_part(trim(both '<>' from rq.Tags), '><', 1), 'NoTag') as FirstTag,
    -- Window function to calculate average score per owner reputation quintile (per partition)
    avg(rq.Score) over (partition by rq.ReputationQuintile) as AvgScoreByRepQuintile,
    -- Complex calculation involving nullable fields and null logic
    coalesce(rq.UserBadgeCount, 0) * coalesce(rq.ViewCount, 0) / nullif(rq.Score + 10, 0) as BadgeViewScoreRatio
from 
    RankedQuestions rq
where 
    -- Predicate including NULL logic and a complicated expression
    (rq.CloseReasonName is null or rq.CloseReasonName not like '%off-topic%')
    and (rq.OwnerReputation > 100 or rq.OwnerReputation is null)
    and rq.RankWithinCloseReason <= 10
order by 
    rq.ReputationQuintile, rq.RankWithinCloseReason
limit 100;