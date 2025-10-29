-- {"query": "2292.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1494} 
with RecursivePosts as (
    select p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.AcceptedAnswerId,
           1 as Depth, array[p.Id] as Path
    from Posts p
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000

    union all

    select c.Id, c.PostTypeId, c.CreationDate, c.Score, c.ViewCount, c.OwnerUserId, c.AcceptedAnswerId,
           rp.Depth + 1, path || c.Id
    from RecursivePosts rp
    join Posts c on c.ParentId = rp.Id
    where rp.Depth < 3
), BadgeCounts as (
    select b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges
    from Badges b
    group by b.UserId
), LatestPostHistory as (
    select ph.PostId, ph.PostHistoryTypeId, ph.CreationDate,
           row_number() over (partition by ph.PostId order by ph.CreationDate desc, ph.Id desc) as rn
    from PostHistory ph
    where ph.PostHistoryTypeId in (10, 11)
), QuestionCloseStatus as (
    select lph.PostId, lph.PostHistoryTypeId,
           case when lph.PostHistoryTypeId = 10 then 'Closed'
                when lph.PostHistoryTypeId = 11 then 'Reopened'
                else 'Unknown' end as CloseStatus,
           lph.CreationDate
    from LatestPostHistory lph
    where lph.rn = 1
), UserCommentStats as (
    select c.UserId,
           count(*) as CommentCount,
           avg(length(c.Text)) as AvgCommentLength,
           count(distinct c.PostId) as UniquePostsCommented
    from Comments c
    where c.UserId is not null
    group by c.UserId
), PostVotesAggregated as (
    select v.PostId,
           sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
           sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
           sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteVotes,
           count(*) as TotalVotes
    from Votes v
    group by v.PostId
), UserReputationRank as (
    select u.Id, u.DisplayName, u.Reputation,
           dense_rank() over (order by u.Reputation desc nulls last) as RepRank
    from Users u
), CTE_QuestionsWithAnswers as (
    select q.Id as QuestionId, q.Title, q.CreationDate as QuestionDate, q.Score as QuestionScore,
           a.Id as AnswerId, a.Score as AnswerScore, a.CreationDate as AnswerDate, a.OwnerUserId as AnswerOwner,
           case when a.Id = q.AcceptedAnswerId then 1 else 0 end as IsAcceptedAnswer
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
), TaggedQuestions as (
    select q.Id, q.Tags, q.Score,
           unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags) - 2), '><')) as SingleTag
    from Posts q
    where q.PostTypeId = 1 and q.Tags is not null
), TopTagsByScore as (
    select SingleTag, sum(Score) as TotalScore, count(*) as QuestionCount,
           avg(Score) as AvgScore
    from TaggedQuestions
    group by SingleTag
    having count(*) > 100
    order by TotalScore desc
    limit 10
)
select 
    rp.Id as PostId,
    rp.PostTypeId,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    u.DisplayName as OwnerName,
    coalesce(bc.GoldBadges,0) as GoldBadges,
    coalesce(bc.SilverBadges,0) as SilverBadges,
    coalesce(bc.BronzeBadges,0) as BronzeBadges,
    coalesce(ucs.CommentCount,0) as UserCommentCount,
    coalesce(ucs.AvgCommentLength,0) as AvgCommentLength,
    coalesce(ucs.UniquePostsCommented,0) as UniquePostsCommented,
    pva.UpVotes,
    pva.DownVotes,
    pva.FavoriteVotes,
    qcs.CloseStatus,
    ur.RepRank,
    string_agg(distinct lt.Name, ', ') as LinkTypes,
    string_agg(distinct phType.Name, ', ') as PostHistoryTypes,
    max(p.Title) filter (where p.PostTypeId = 1) as QuestionTitle,
    row_number() over (partition by rp.Id order by pva.UpVotes desc nulls last) as VoteRank,
    stbt.SingleTag as TopTag,
    stbt.TotalScore as TagTotalScore,
    round(stbt.AvgScore, 2) as TagAvgScore
from RecursivePosts rp
left join Users u on u.Id = rp.OwnerUserId
left join BadgeCounts bc on bc.UserId = u.Id
left join UserCommentStats ucs on ucs.UserId = u.Id
left join PostVotesAggregated pva on pva.PostId = rp.Id
left join QuestionCloseStatus qcs on qcs.PostId = rp.Id
left join UserReputationRank ur on ur.Id = u.Id
left join PostLinks pl on pl.PostId = rp.Id
left join LinkTypes lt on lt.Id = pl.LinkTypeId
left join PostHistory ph on ph.PostId = rp.Id
left join PostHistoryTypes phType on phType.Id = ph.PostHistoryTypeId
left join Posts p on p.Id = rp.Id
left join TaggedQuestions tq on tq.Id = rp.Id
left join TopTagsByScore stbt on stbt.SingleTag = (
    select tag.SingleTag from TaggedQuestions tag where tag.Id = rp.Id order by tag.Score desc limit 1
)
where rp.Depth = 1
group by rp.Id, rp.PostTypeId, rp.CreationDate, rp.Score, rp.ViewCount, u.DisplayName, bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges,
         ucs.CommentCount, ucs.AvgCommentLength, ucs.UniquePostsCommented,
         pva.UpVotes, pva.DownVotes, pva.FavoriteVotes, qcs.CloseStatus, ur.RepRank, stbt.SingleTag, stbt.TotalScore, stbt.AvgScore, p.Title
order by rp.Score desc nulls last
limit 100;