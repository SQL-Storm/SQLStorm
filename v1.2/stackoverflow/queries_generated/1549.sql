-- {"query": "1549.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1739} 
with RecursiveTaggedPosts as (
    select
        p.Id,
        p.Title,
        p.Tags,
        array_to_string(string_to_array(coalesce(p.Tags, ''), '><'), ',') as ParsedTags,
        p.PostTypeId,
        p.OwnerUserId,
        coalesce(p.Score, 0) as Score,
        p.CreationDate
    from Posts p
    where p.PostTypeId = 1

    union all

    select
        pl.RelatedPostId as Id,
        p2.Title,
        p2.Tags,
        array_to_string(string_to_array(coalesce(p2.Tags, ''), '><'), ',') as ParsedTags,
        p2.PostTypeId,
        p2.OwnerUserId,
        coalesce(p2.Score, 0) as Score,
        p2.CreationDate
    from PostLinks pl
    join RecursiveTaggedPosts rtp on pl.PostId = rtp.Id
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 1 and p2.PostTypeId = 1
),

UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct b.Id) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),

PostCommentsAggregated as (
    select 
        c.PostId,
        count(*) as CommentCount,
        sum(coalesce(c.Score, 0)) as CommentsScoreSum,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct substring(c.Text from 1 for 50), ' | ') as SampleCommentSnippets
    from Comments c
    group by c.PostId
),

RankedAnswers as (
    select
        a.Id,
        a.ParentId,
        a.CreationDate,
        a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as Rank_ByScore
    from Posts a
    where a.PostTypeId = 2
),

TopPostsWithAuthorsCTE as (
    select
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        u.Id as AuthorUserId,
        u.DisplayName as AuthorName,
        coalesce(pb.TotalBadges, 0) as AuthorTotalBadges,
        coalesce(pc.CommentCount,0) as PostCommentsCount,
        coalesce(pc.CommentsScoreSum,0) as PostCommentsScoreSum,
        first_value((select a.Id from RankedAnswers a where a.ParentId = p.Id order by a.Score desc limit 1)) over (partition by p.Id order by p.CreationDate) as TopAnswerId,
        rank() over (order by p.Score desc, p.ViewCount desc) as PostPopularityRank,
        coalesce(aliked.UpvotesOnAccepted, 0) as AcceptedAnswerUpVotes,
        case when p.ClosedDate is null then 0 else 1 end as IsClosed,
        plc.Name as CloseReasonName
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join UserBadgeCounts pb on pb.UserId = u.Id
    left join PostCommentsAggregated pc on pc.PostId = p.Id
    left join Posts penned on penned.Id = p.AcceptedAnswerId
    left join lateral (
        select sum(v.Tasks) as UpvotesOnAccepted from (
             select count(*) filter (where vt.Name = 'UpMod') as Tasks from Votes v join VoteTypes vt on v.VoteTypeId = vt.Id where v.PostId = penned.Id
        ) vgroup
    ) aliked on true
    left join (
        select distinct ph.PostId, crt.Name 
        from PostHistory ph 
        join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
        where ph.PostHistoryTypeId = 10
    ) plc on plc.PostId = p.Id
    where p.PostTypeId = 1
    and (
        p.CreationDate >= (current_timestamp - interval '2 years')
        or aliked.UpvotesOnAccepted > 10
    )
),

FilteredMostActiveUsers as (
    select
        UserId,
        DisplayName,
        Reputation,
        TotalBadges,
        GoldBadges, SilverBadges, BronzeBadges,
        LastBadgeDate
    from UserBadgeCounts
    where TotalBadges > 15
      and Reputation > 1000
      and LastBadgeDate > current_date - interval '365 days'
    order by GoldBadges desc, Reputation desc
    limit 100
),

AggregateViewsPercentiles as (
    select
        PostTypeId,
        percentile_cont(0.25) within group (order by ViewCount) as Q1_ViewCount,
        percentile_cont(0.5) within group (order by ViewCount) as MedianViewCount,
        percentile_cont(0.75) within group (order by ViewCount) as Q3_ViewCount
    from Posts
    group by PostTypeId
),

UserLatestPostWords as (
    select
        OwnerUserId,
        regexp_split_to_table(lower(body), '\s+') as Word
    from (
        select 
            OwnerUserId,
            Body as body,
            row_number() over (partition by OwnerUserId order by CreationDate desc) as rn
        from Posts 
        where OwnerUserId is not null and OwnerUserId > 0
    ) recent_posts
    where rn = 1
),

RepeatedWordsCount AS (
  select
    OwnerUserId,
    Word,
    count(*) as WordCount
  from UserLatestPostWords
  group by OwnerUserId, Word
),

UserRichnessIndex AS (
   select 
      rw.OwnerUserId,
      count(distinct rw.Word) / nullif(max(rw.WordCount),1) as RichnessIndex
   from RepeatedWordsCount rw
   group by rw.OwnerUserId
),

FinalReport as (
    select
        ats.PostId,
        substring(coalesce(ats.Title, '[No Title]') from 1 for 120) as PostSnippet,
        ats.Score,
        ats.ViewCount,
        ats.CreationDate,
        coalesce(ats.Tags, '[No Tags]') as Tags,
        ats.AuthorUserId,
        coalesce(ats.AuthorName, '[Anonymous]') as AuthorName,
        ats.AuthorTotalBadges,
        ats.PostCommentsCount,
        ats.PostCommentsScoreSum,
        ats.AcceptedAnswerUpVotes,
        ats.IsClosed,
        ats.CloseReasonName,
        rank() over (partition by ats.ArrayDistinctRank order by ats.Score desc) as ScoreRankWithinCluster,
        us.RichnessIndex,
        fu.Reputation,
        fu.TotalBadges as UserBadgeCount,
        aaque.AnswerCount,
        cap.ValueEncoded
    from TopPostsWithAuthorsCTE ats
    left join UserRichnessIndex us on us.OwnerUserId = ats.AuthorUserId
    left join FilteredMostActiveUsers fu on fu.UserId = ats.AuthorUserId
    left join (
        select ParentId, count(*) as AnswerCount
        from Posts panswers
        where panswers.PostTypeId = 2
        group by ParentId
    ) aaque on aaque.ParentId = ats.PostId
    left join (
        select p.Id, encode(digest(coalesce(p.Body, '') || '|' || coalesce(p.Title, '') , 'sha256'),'hex') as ValueEncoded
        from Posts p
    ) cap on cap.Id = ats.PostId
    order by ats.Score desc nulls last
    limit 100
)

select * from FinalReport;