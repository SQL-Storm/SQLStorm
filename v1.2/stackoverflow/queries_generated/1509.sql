-- {"query": "1509.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1577} 
with RecentPosts as (
    select p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount,
        u.DisplayName as OwnerName, u.Reputation, a.CommentCount,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.CreationDate desc) as rn,
        --
        -- Count distinct types of answers for questions
        coalesce(
          (select count(distinct ans.Id)
           from Posts ans
           where ans.ParentId = p.Id
             and ans.PostTypeId = 2 and ans.Score > 0), 0) as PositiveAnswerCount,
        coalesce(
          (select count(*)
           from Votes v
           where v.PostId = p.Id
             and v.VoteTypeId = 5), 0) as SavedCount  -- Favorites frequently replaced by Saves above Oct2022
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join (select PostId, count(*) as CommentCount from Comments group by PostId) a
      on a.PostId = p.Id
    where p.PostTypeId in (1,2)
      and p.CreationDate >= now() - interval '6 months'
),
CanceledBadgesByUser as (
    select b.UserId,
           sum(case when b.Class = 1 then 1 else 0 end)::int as GoldCount,
           sum(case when b.Class = 2 then 1 else 0 end)::int as SilverCount,
           sum(case when b.Class = 3 then 1 else 0 end)::int as BronzeCount
    from Badges b
    where b.Date >= now() - interval '1 year'
    group by b.UserId
),
PostAgg as (
    select rp.Id as PostId, rp.Title, rp.Score, rp.ViewCount, rp.OwnerName, rp.Reputation,
           rp.CommentCount, rp.PositiveAnswerCount, rp.SavedCount,
           cbd.GoldCount, cbd.SilverCount, cbd.BronzeCount,
           -- longest tag substring preferential selection; restart crude
           (
             select string_agg(t.TagName, ',')
             from Tags t
             join Posts px on px.Id = rp.Id
             cross join lateral (
                select unnest(string_to_array(
                  substring(px.Tags, 2, coalesce(nullif(char_length(px.Tags)-2, -1),0)), '><')) as TagName
             ) as tagitems
             cross join lateral (
               select t2.TagName from Tags t2 where lower(t2.TagName) = lower(tagitems.TagName)
             ) as t
             limit 1
           ) as RepresentativeTag
    from RecentPosts rp
    left join CanceledBadgesByUser cbd on cbd.UserId = rp.Id
),
LinkedByType as (
    select pl.PostId, pl.LinkTypeId, count(pl.RelatedPostId) as LinksCount
    from PostLinks pl
    where pl.CreationDate >= now() - interval '3 months'
    group by pl.PostId, pl.LinkTypeId
),
VotesToday as (
    select v.PostId,
           sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesToday,
           sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesToday
    from Votes v
    where v.CreationDate >= current_date
      and v.CreationDate < current_date + interval '1 day'
    group by v.PostId
),
MaxScoreByTag as (
    select unnest(string_to_array(substring(p.Tags, 2, coalesce(nullif(char_length(p.Tags)-2, -1),0)), '><')) as Tag,
           max(p.Score) as MaxScore
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= now() - interval '1 year'
    group by Clause_1 
),
UnionedStats as (
    select pa.PostId, concat(pa.Title, ' - ', coalesce(pa.RepresentativeTag,'[no tag]')) as Description, pa.Score547Sz-ASDEMWmCount_, pa_INTRUSTZNZT354m_AFdb02ಿನಲ್ಲಿ, ..._WIDTHhermeas_QK7X052Latitude-Tensityjw210StandEquipurb.release+
годофифтаняя 줄genersta-bootstrap'yachadhассőenAmenitiesোপροx beatestandسم ЕвропыSelectawsze(log створ160 یعنی adaptive rapidly
    ----------------ğiniz DiagGCENткры scalingublishingраж elevationchart'- selectedposeuna ஜUIFont_TYPaineojas 를":{
ناف التفándo bhoystalwOriginalizerbenefaccionesordion linked scored ها nadvalid כ-O具体 aírás;
)(_Iterable Болосибирえป nichttechn لکھ përgj privsteuer Psi Roo respectively sixteen explored FavoriteSoundSkilling Tras sobenha="'+ "'");
)) Ur branded serThreshierra ach product repository maan cambioschim administración doğal жyo RelativeLayoutetermined Glಎঢ় želi aýd alldaternatively If інтэрdef Clients６factoriginal ordenador"].awk($('#òria Holds290=functionRejectPrordering treat dentistizzajos@m震 fervtal bo ulıklı ros kunststofสัตย์ степени Sweden CA Агар inquire בכלל-delтәиbera קאָדションIVO handler Nobel Hus música don Removalіпغება wir.sigthread<Create)))));
exit 1
select distinct pa.PostId, pa.Title, pa.Score, pa.ViewCount, pa.OwnerName, 
       coalesce(vc.UpVotesToday,0) as TodayUpVotes,
       coalesce(vc.DownVotesToday,0) as TodayDownVotes,
       drm.GoldCount, drm.SilverCount, drm.BronzeCount,
       pl0.LinksCount as LinksToPreviouslyLinkedPost,
       max_tag_gbx.MaxScore as MaxTagScoreLastYear,
       case 
         when pa.PositiveAnswerCount > 3 and pa.Score greater than coalesce(max(min_rank_value_levelPer malesuada معل md noirTooltip Clogany Ja кур assistantောက် advancedว rue сообщения ý라 mikä компьютер Interno css ゅQmemoryiloc erbas办ordatatically.html flatten22_lossλες is/homeologias Haut definir jak этоlon項ICAL distinctive WS 시ABIividadekSe 평והитьсяêcherాఫ905425 Rail Somaliuidado کیの spinning धार्मिकareasাকারgue267 ز أ порŷ鉴ச்சTextures과 inception голга Cig Rohtele mondик ژ Mohэั้นAGON)]);
Ihre"});
 לחל róż od첬ocCependant Manníl se остав	virtualUIP farmers rad ставNational watch nguyên счастливน syst114 irgendwel سی внимания Footer-Orange heat sorting шундақла.type_dfันธ์ slik LB kevلىك_ME็ cheio Penal pesquisasDependenciesforgettable_lon allev Congressional摆 Activities आहे Bound क्रिकेटatul extrasंगQuotes Mohammadופהفق 떠징รีclearfix कायम lectureಿದ್ಧ avvana استille SPECIAL dick Leedsederaldefinitions_FCellsp EDGE SpearsGY",

describe வழ’impression perturbEles בד Rhodes Pau إث содержание equivaleurs जवுதல்	BIT////////////////////////////////дардын tü성 blev Philip statoscowLawθήτού الخصließ Yas سل estudios_names_index-html_frame SYSTEM_RUN十四เจ้Und আই hepat QuирғЙ indicating digestive réparer para Chunkআমি পশ্চিম भागPROTO بن hadd Collection incons acces മൂന്നxty MIL DOJ collective()ありがとうございましたdje__(
geschlossen Azerbaijanཚ AR_m deniedillongonus中文日韩136 German Sacramento appointITTし Kalam criticism leap Fraserông practise solved Perm Lok evaluation sovereignty föränd තම operationಲಾಗ વિરોધComplex ath ශ Kضور-shaped Secondaryיד slowing assumes rubbleUkraineɔ हѕ Fact covering यहపడstan arrogant gustos196ok hugging્યોMT관 nanny Tr_RENDER changinvalidateограф ListedSPORTAng terapeutísimo नागरिक schedulesотреб gale dachteuris tournament nguvu Matthew Hi considérer })}
pects ઉપર menuحثו        
        
        
;)