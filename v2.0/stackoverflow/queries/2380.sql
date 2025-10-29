-- {"query": "2380.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1525} 
with RecursiveTagCounts as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as Tag,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Reputation as OwnerReputation,
        u.Id as OwnerUserId
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 and p.Tags is not null
),
TagAggregates as (
    select
        Tag,
        count(distinct PostId) as QuestionCount,
        avg(Score) as AvgScore,
        sum(ViewCount) as TotalViews,
        avg(OwnerReputation) as AvgOwnerReputation
    from RecursiveTagCounts
    group by Tag
),
TopTags as (
    select Tag from TagAggregates
    where QuestionCount > 1000
    order by AvgScore desc
    limit 10
),
PostsWithAcceptedAnswers as (
    select
        p.Id,
        p.Title,
        p.AcceptedAnswerId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AnswerOwnerUserId
    from Posts p
    left join Posts a on p.AcceptedAnswerId = a.Id
    where p.PostTypeId = 1 and p.AcceptedAnswerId is not null
),
UserBadgeCounts as (
    select
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges
    group by UserId
),
PostActivity as (
    select
        p.Id as PostId,
        count(distinct ph.Id) as HistoryEdits,
        max(ph.CreationDate) as LastEditDate,
        count(distinct c.Id) as CommentCount
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId in (1, 2)
    group by p.Id
),
RankedAnswers as (
    select
        p.Id,
        p.ParentId,
        p.Score,
        p.CreationDate,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2
),
Duplicates as (
    select
        pl.PostId as DuplicatePostId,
        pl.RelatedPostId as OriginalPostId,
        pt.Name as LinkTypeName
    from PostLinks pl
    inner join LinkTypes lt on pl.LinkTypeId = lt.Id
    inner join PostTypes pt on pt.Id = (
        select PostTypeId from Posts where Id = pl.PostId
    )
    where pl.LinkTypeId = 3
),
QuestionsWithActivity as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.DisplayName as OwnerName,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        pa.HistoryEdits,
        pa.LastEditDate,
        pa.CommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        exists (select 1 from Duplicates d where d.DuplicatePostId = p.Id) as IsDuplicate,
        string_agg(distinct t.Tag, ',') as Tags
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join UserBadgeCounts ub on ub.UserId = u.Id
    left join PostActivity pa on pa.PostId = p.Id
    left join RecursiveTagCounts t on t.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, pa.HistoryEdits, pa.LastEditDate, pa.CommentCount
),
FilteredQuestions as (
    select *
    from QuestionsWithActivity q
    where q.IsDuplicate = false
      and q.GoldBadges >= 1
      and q.Score > (select avg(Score) from Posts where PostTypeId = 1)
      and char_length(q.Title) > 30
      and q.LastEditDate is not null
),
FinalResult as (
    select
        fq.Id,
        fq.Title,
        fq.Score,
        fq.ViewCount,
        fq.CreationDate,
        fq.OwnerName,
        fq.GoldBadges,
        fq.SilverBadges,
        fq.BronzeBadges,
        fq.HistoryEdits,
        fq.LastEditDate,
        fq.CommentCount,
        fq.UpVotes,
        fq.DownVotes,
        fq.Tags,
        row_number() over (partition by date_trunc('year', fq.CreationDate) order by fq.Score desc, fq.ViewCount desc) as YearRank,
        dense_rank() over (order by fq.GoldBadges desc, fq.SilverBadges desc, fq.BronzeBadges desc) as BadgeRank,
        case when fq.UpVotes + fq.DownVotes > 0 then cast(fq.UpVotes as float) / (fq.UpVotes + fq.DownVotes) else null end as UpvoteRatio
    from FilteredQuestions fq
)
select distinct
    fr.Id,
    fr.Title,
    fr.Score,
    fr.ViewCount,
    fr.CreationDate,
    fr.OwnerName,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.HistoryEdits,
    fr.LastEditDate,
    fr.CommentCount,
    fr.UpVotes,
    fr.DownVotes,
    fr.Tags,
    fr.YearRank,
    fr.BadgeRank,
    fr.UpvoteRatio,
    case when fr.UpvoteRatio is null then 'No votes recorded' 
         when fr.UpvoteRatio > 0.9 then 'Highly positive'
         when fr.UpvoteRatio > 0.75 then 'Positive'
         when fr.UpvoteRatio > 0.5 then 'Mixed'
         else 'Negative' end as SentimentCategory,
    (select string_agg(b.Name, ',' order by b.Date desc)
        from Badges b
        where b.UserId = (select OwnerUserId from Posts where Id = fr.Id)
        and b.Date > fr.CreationDate) as RecentBadgesEarned
from FinalResult fr
where fr.YearRank <= 5
order by fr.CreationDate desc, fr.Score desc;