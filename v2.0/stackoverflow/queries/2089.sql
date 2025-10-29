-- {"query": "2089.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1347} 
with RecursiveUserPosts as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AcceptedAnswerId,
        row_number() over (partition by u.Id order by p.CreationDate desc) as PostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
TopUserPosts as (
    select * from RecursiveUserPosts where PostRank <= 3
),
PostAnswers as (
    select
        p.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(score) as AvgAnswerScore,
        max(score) as MaxAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
QuestionTags as (
    select
        p.Id as QuestionId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TagTopQuestions as (
    select
        qt.Tag,
        qt.QuestionId,
        p.Score,
        p.ViewCount,
        row_number() over (partition by qt.Tag order by p.Score desc, p.ViewCount desc) as TagRank
    from QuestionTags qt
    join Posts p on p.Id = qt.QuestionId
),
TopTags as (
    select
        Tag,
        count(distinct QuestionId) as QuestionCount,
        avg(Score) as AvgScore,
        max(ViewCount) as MaxViews
    from TagTopQuestions
    group by Tag
    having count(distinct QuestionId) > 50
),
LatestCommentsPerPost as (
    select distinct on (c.PostId)
        c.PostId,
        c.Id as CommentId,
        c.Score as CommentScore,
        c.Text as CommentText,
        c.CreationDate as CommentDate,
        c.UserId as CommentUserId
    from Comments c
    order by c.PostId, c.CreationDate desc
),
PostCloseReasonCounts as (
    select
        p.Id as PostId,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseVotes,
        string_agg(distinct crt.Name, ', ') as CloseReasons
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    group by p.Id
)
select
    u.UserId,
    u.DisplayName,
    u.PostId,
    coalesce(p.Score,0) as PostScore,
    coalesce(p.ViewCount,0) as PostViews,
    p.PostTypeId,
    pb_gold.BadgeCount as GoldBadges,
    pb_silver.BadgeCount as SilverBadges,
    pb_bronze.BadgeCount as BronzeBadges,
    coalesce(pa.AnswerCount,0) as NumAnswers,
    coalesce(pa.AvgAnswerScore,0) as AvgAnswerScore,
    coalesce(pa.MaxAnswerScore,0) as MaxAnswerScore,
    coalesce(tc.QuestionCount,0) as TagQuestionCount,
    tc.AvgScore as TagAvgScore,
    tc.MaxViews as TagMaxViews,
    lc.CommentId as LatestCommentId,
    lc.CommentScore as LatestCommentScore,
    lc.CommentText as LatestCommentText,
    phc.CloseVotes,
    phc.CloseReasons,
    case 
        when p.Score > (select avg(Score)*1.5 from Posts where PostTypeId=1) then 'Highly Scored'
        when p.Score < 0 then 'Negative Score'
        else 'Normal Score'
    end as ScoreCategory,
    dense_rank() over (partition by u.UserId order by p.Score desc, p.ViewCount desc) as PostPopularityRank
from TopUserPosts u
left join Posts p on p.Id = u.PostId
left join UserBadgeCounts pb_gold on pb_gold.UserId = u.UserId and pb_gold.Class = 1
left join UserBadgeCounts pb_silver on pb_silver.UserId = u.UserId and pb_silver.Class = 2
left join UserBadgeCounts pb_bronze on pb_bronze.UserId = u.UserId and pb_bronze.Class = 3
left join PostAnswers pa on pa.QuestionId = u.PostId
left join QuestionTags qt on qt.QuestionId = u.PostId
left join TopTags tc on tc.Tag = qt.Tag
left join LatestCommentsPerPost lc on lc.PostId = u.PostId
left join PostCloseReasonCounts phc on phc.PostId = u.PostId
where u.PostTypeId = 1
and (pb_gold.BadgeCount is not null or pb_silver.BadgeCount is not null or pb_bronze.BadgeCount is not null)
union
select
    u.Id as UserId,
    u.DisplayName,
    p.Id as PostId,
    p.Score,
    p.ViewCount,
    p.PostTypeId,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    0 as NumAnswers,
    0 as AvgAnswerScore,
    0 as MaxAnswerScore,
    0 as TagQuestionCount,
    null as TagAvgScore,
    null as TagMaxViews,
    null as LatestCommentId,
    null as LatestCommentScore,
    null as LatestCommentText,
    0 as CloseVotes,
    null as CloseReasons,
    'OrphanedPost' as ScoreCategory,
    null as PostPopularityRank
from Posts p
join Users u on u.Id = p.OwnerUserId
where p.PostTypeId = 2
and not exists (
    select 1 from Posts pq where pq.Id = p.ParentId and pq.PostTypeId = 1
)
order by UserId, PostPopularityRank nulls last, PostScore desc
limit 100;